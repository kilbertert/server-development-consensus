#!/usr/bin/env bash
set -euo pipefail

# The reaper decides whether to remove containers, so the assertions that matter
# are the ones about what it refuses to touch. These run against stubbed
# docker/gh/ps so no real container is ever involved.

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
mkdir -p "$HOME/.local/bin" "$tmp/stub" "$HOME/Projects/_runners/test-runner"
# A runner config makes the repository list discoverable, as on the host.
cat >"$HOME/Projects/_runners/test-runner/.runner" <<'EOF'
{ "gitHubUrl": "https://github.com/kilbertert/genesis-evidence" }
EOF

tool="$base_dir/bin/dev-reap-sandbox"
[ -x "$tool" ] || { echo "FAIL: $tool is not executable"; exit 1; }

# --- stubs -----------------------------------------------------------------
# `ps` reports what the test wants for runner workers.
cat >"$tmp/stub/ps" <<'EOF'
#!/usr/bin/env bash
if [ -n "${STUB_RUNNER_WORKERS:-}" ]; then
  printf '%s\n' "Runner.Worker"
fi
exit 0
EOF

# `gh` reports active runs per STUB_ACTIVE_RUNS.
cat >"$tmp/stub/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${STUB_ACTIVE_RUNS:-0}"
exit 0
EOF

# `docker ps` lists STUB_CONTAINERS (name:age-hours); `docker inspect` answers
# with a Created timestamp that many hours ago; `docker rm` records the call.
cat >"$tmp/stub/docker" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  ps)
    # Expose only the NAME; the age is looked up separately by inspect.
    printf '%s\n' ${STUB_CONTAINERS:-} | cut -d: -f1
    ;;
  inspect)
    # `docker inspect NAME --format ...`; NAME is the 2nd argument.
    name=$2
    hours=$(printf '%s\n' ${STUB_CONTAINERS:-} | awk -F: -v n="$name" '$1==n{print $2}')
    printf '%s\n' "$(date -u -d "-${hours} hours" +%Y-%m-%dT%H:%M:%SZ)"
    ;;
  rm)
    # `docker rm -f NAME`; NAME is the last argument.
    printf '%s\n' "${!#}" >>"$STUB_RM_LOG" ;;
esac
exit 0
EOF
chmod +x "$tmp/stub/ps" "$tmp/stub/gh" "$tmp/stub/docker"
export PATH="$tmp/stub:$PATH"
export STUB_RM_LOG="$tmp/removed.txt"
: >"$STUB_RM_LOG"

fail=0
# Assert on a command's exit status without letting `set -e` abort the run:
# a failing assertion must be recorded, not fatal.
check() { # check <description> <command...>
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "  ok   $desc"
  else
    echo "  FAIL $desc" >&2
    fail=1
  fi
}
not_empty() { [ -s "$1" ]; }
is_empty() { [ ! -s "$1" ]; }

echo "T1 dry run lists an old container but removes nothing"
out=$(STUB_CONTAINERS="sandcastle-old:50" "$tool" 2>&1)
check "identifies the orphan" grep -q "would reap sandcastle-old" <<<"$out"
check "removed nothing" is_empty "$STUB_RM_LOG"
check "says it is a dry run" grep -q "dry run" <<<"$out"

echo "T2 a fresh container is kept"
out=$(STUB_CONTAINERS="sandcastle-new:1" "$tool" --apply 2>&1)
check "keeps a young container" grep -q "keep    sandcastle-new" <<<"$out"
check "did not remove it" is_empty "$STUB_RM_LOG"

echo "T3 --apply removes an old container"
: >"$STUB_RM_LOG"
STUB_CONTAINERS="sandcastle-old:50" "$tool" --apply >/dev/null 2>&1
check "removed the orphan" grep -q "sandcastle-old" "$STUB_RM_LOG"

echo "T4 an active CI run stops everything (fail-closed)"
: >"$STUB_RM_LOG"
STUB_CONTAINERS="sandcastle-old:50" STUB_ACTIVE_RUNS=1 "$tool" --apply >/dev/null 2>&1
check "removed nothing while a run is active" is_empty "$STUB_RM_LOG"

echo "T5 a runner worker present stops everything (fail-closed)"
: >"$STUB_RM_LOG"
STUB_CONTAINERS="sandcastle-old:50" STUB_RUNNER_WORKERS=1 "$tool" --apply >/dev/null 2>&1
check "removed nothing while a worker is present" is_empty "$STUB_RM_LOG"

echo "T6 a container that is not ours is never touched"
: >"$STUB_RM_LOG"
STUB_CONTAINERS="someone-elses-container:999" "$tool" --apply >/dev/null 2>&1
check "left a foreign container alone" is_empty "$STUB_RM_LOG"

echo "T7 --max-age-hours is respected"
: >"$STUB_RM_LOG"
STUB_CONTAINERS="sandcastle-x:3" "$tool" --apply --max-age-hours 2 >/dev/null 2>&1
check "removed past the custom threshold" grep -q "sandcastle-x" "$STUB_RM_LOG"

echo "T8 an unreadable gh response stops everything (fail-closed)"
: >"$STUB_RM_LOG"
# gh exits nonzero -> the reaper must not treat that as "no active runs".
cat >"$tmp/stub/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$tmp/stub/gh"
STUB_CONTAINERS="sandcastle-old:50" "$tool" --apply >/dev/null 2>&1
check "removed nothing when the run list is unreadable" is_empty "$STUB_RM_LOG"

echo "T9 a non-numeric run count stops everything (fail-closed)"
: >"$STUB_RM_LOG"
cat >"$tmp/stub/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "not-a-number"
STUB
chmod +x "$tmp/stub/gh"
STUB_CONTAINERS="sandcastle-old:50" "$tool" --apply >/dev/null 2>&1
check "removed nothing on a non-numeric count" is_empty "$STUB_RM_LOG"

echo "T10 a removal failure exits nonzero"
restore_gh() {
  cat >"$tmp/stub/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${STUB_ACTIVE_RUNS:-0}"
STUB
  chmod +x "$tmp/stub/gh"
}
restore_gh
cat >"$tmp/stub/docker" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  ps) printf '%s\n' ${STUB_CONTAINERS:-} | cut -d: -f1 ;;
  inspect) printf '%s\n' "$(date -u -d "-50 hours" +%Y-%m-%dT%H:%M:%SZ)" ;;
  rm) exit 1 ;;   # removal always fails
esac
exit 0
STUB
chmod +x "$tmp/stub/docker"
if STUB_CONTAINERS="sandcastle-old:50" "$tool" --apply >/dev/null 2>&1; then
  echo "  FAIL removal failure should exit nonzero" >&2; fail=1
else
  echo "  ok   removal failure exits nonzero"
fi

echo "T11 no runner config stops everything (fail-closed)"
: >"$STUB_RM_LOG"
mv "$HOME/Projects/_runners" "$tmp/runners-hidden"
STUB_CONTAINERS="sandcastle-old:50" "$tool" --apply >/dev/null 2>&1
check "removed nothing without runner configuration" is_empty "$STUB_RM_LOG"
mv "$tmp/runners-hidden" "$HOME/Projects/_runners"

echo
if [ "$fail" -ne 0 ]; then echo "dev-reap-sandbox tests FAILED"; exit 1; fi
echo "dev-reap-sandbox tests passed"
