#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
sync_tool=$base_dir/bin/sync-privileged-policy
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export SERVER_POLICY_PRIVILEGED_SYNC_TESTING=1
export SERVER_POLICY_PRIVILEGED_SYNC_ROOT=$tmp/root
[ "$(head -n 1 "$sync_tool")" = '#!/usr/bin/python3' ]

canonical=$tmp/root/home/claude/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md
targets='etc/agent-governance/server-development-consensus.md
home/claude/.codex/AGENTS.md
home/claude/.codex/AGENTS.override.md
home/claude/.claude/CLAUDE.md'
export SERVER_POLICY_PRIVILEGED_SYNC_TEST_IMMUTABLE_TARGETS=/home/claude/.codex/AGENTS.md,/home/claude/.codex/AGENTS.override.md,/home/claude/.claude/CLAUDE.md
mode_for_index() {
  case $1 in
    1) printf '%s\n' 600 ;;
    2) printf '%s\n' 640 ;;
    3) printf '%s\n' 644 ;;
    4) printf '%s\n' 600 ;;
  esac
}
mkdir -p "$(dirname "$canonical")"
printf '%s\n' \
  '# Server Development Consensus' \
  '## Internal Knowledge And Public Projection Boundary' \
  'private by default' >"$canonical"
expected_sha256=$(sha256sum "$canonical" | awk '{print $1}')

index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  target=$tmp/root/$relative
  mkdir -p "$(dirname "$target")"
  printf 'old-%s\n' "$index" >"$target"
  chmod "$(mode_for_index "$index")" "$target"
done

if "$sync_tool" --verify --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL drifted privileged mirrors passed verification' >&2
  exit 1
fi

sync_output=$("$sync_tool" --expected-sha256 "$expected_sha256")
printf '%s\n' "$sync_output" | grep -q 'privileged policy sync complete: backup='
"$sync_tool" --verify --expected-sha256 "$expected_sha256" |
  grep -q 'privileged policy verification: failures=0'
if SERVER_POLICY_PRIVILEGED_SYNC_TEST_IMMUTABLE_TARGETS= \
  "$sync_tool" --verify --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL mutable privileged mirrors passed verification' >&2
  exit 1
fi

index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  target=$tmp/root/$relative
  cmp "$canonical" "$target"
  [ "$(stat -c '%a' "$target")" = "$(mode_for_index "$index")" ]
done

unsafe_target=$tmp/root/home/claude/.codex/AGENTS.md
chmod 664 "$unsafe_target"
if "$sync_tool" --verify --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL group-writable privileged mirror passed verification' >&2
  exit 1
fi
backup_count_before=$(find "$tmp/root/var/backups/server-development-consensus" \
  -mindepth 1 -maxdepth 1 -type d | wc -l)
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL group-writable privileged mirror was accepted for sync' >&2
  exit 1
fi
[ "$(find "$tmp/root/var/backups/server-development-consensus" \
  -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$backup_count_before" ]
chmod 640 "$unsafe_target"

backup_dir=$(printf '%s\n' "$sync_output" | sed -n 's/^privileged policy sync complete: backup=//p')
python3 - "$backup_dir/manifest.json" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest["status"] == "completed"
assert len(manifest["targets"]) == 4
assert all(item["after"]["sha256"] == manifest["source"]["sha256"] for item in manifest["targets"])
for index, item in enumerate(manifest["targets"], start=1):
    backup = Path(sys.argv[1]).parent / item["backup"]
    assert backup.read_text() == f"old-{index}\n"
    assert f"{backup.stat().st_mode & 0o777:04o}" == item["before"]["mode"]
    assert item["before"]["immutable"] == (index != 1)
    assert item["after"]["immutable"] == (index != 1)
PY
[ "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readlines()[-1])["result"])' <"$tmp/root/var/log/server-development-consensus/privileged-sync.jsonl")" = completed ]

printf '%s\n' "$targets" | while IFS= read -r relative; do
  printf '%s\n' rollback-old >"$tmp/root/$relative"
done
printf '%s\n' \
  '# Server Development Consensus' \
  '## Internal Knowledge And Public Projection Boundary' \
  'new private boundary' >"$canonical"
expected_sha256=$(sha256sum "$canonical" | awk '{print $1}')
export SERVER_POLICY_PRIVILEGED_SYNC_FAIL_AFTER=2
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL injected privileged sync failure returned success' >&2
  exit 1
fi
unset SERVER_POLICY_PRIVILEGED_SYNC_FAIL_AFTER
printf '%s\n' "$targets" | while IFS= read -r relative; do
  [ "$(cat "$tmp/root/$relative")" = rollback-old ]
done
[ "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readlines()[-1])["result"])' <"$tmp/root/var/log/server-development-consensus/privileged-sync.jsonl")" = rolled_back ]

printf '%s\n' "$targets" | while IFS= read -r relative; do
  printf '%s\n' rollback-again >"$tmp/root/$relative"
done
printf '%s\n' \
  '# Server Development Consensus' \
  '## Internal Knowledge And Public Projection Boundary' \
  'third private boundary' >"$canonical"
expected_sha256=$(sha256sum "$canonical" | awk '{print $1}')
export SERVER_POLICY_PRIVILEGED_SYNC_FAIL_AFTER=2
export SERVER_POLICY_PRIVILEGED_SYNC_FAIL_RESTORE_INDEX=1
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL restore-failure injection returned success' >&2
  exit 1
fi
unset SERVER_POLICY_PRIVILEGED_SYNC_FAIL_AFTER
unset SERVER_POLICY_PRIVILEGED_SYNC_FAIL_RESTORE_INDEX
cmp "$canonical" "$tmp/root/etc/agent-governance/server-development-consensus.md"
printf '%s\n' "$targets" | tail -n +2 | while IFS= read -r relative; do
  [ "$(cat "$tmp/root/$relative")" = rollback-again ]
done
[ "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readlines()[-1])["result"])' <"$tmp/root/var/log/server-development-consensus/privileged-sync.jsonl")" = rollback_failed ]

index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  printf 'post-replace-old-%s\n' "$index" >"$tmp/root/$relative"
done
printf '%s\n' \
  '# Server Development Consensus' \
  '## Internal Knowledge And Public Projection Boundary' \
  'post-replace private boundary' >"$canonical"
expected_sha256=$(sha256sum "$canonical" | awk '{print $1}')
export SERVER_POLICY_PRIVILEGED_SYNC_FAIL_REPLACE_POST_INDEX=2
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL post-replace failure injection returned success' >&2
  exit 1
fi
unset SERVER_POLICY_PRIVILEGED_SYNC_FAIL_REPLACE_POST_INDEX
index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  [ "$(cat "$tmp/root/$relative")" = "post-replace-old-$index" ]
done
[ "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.readlines()[-1])["result"])' <"$tmp/root/var/log/server-development-consensus/privileged-sync.jsonl")" = rolled_back ]

index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  printf 'swap-old-%s\n' "$index" >"$tmp/root/$relative"
done
printf '%s\n' \
  '# Server Development Consensus' \
  '## Internal Knowledge And Public Projection Boundary' \
  'swap protected boundary' >"$canonical"
expected_sha256=$(sha256sum "$canonical" | awk '{print $1}')
export SERVER_POLICY_PRIVILEGED_SYNC_SWAP_PREPARED_INDEX=1
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL swapped prepared replacement was installed' >&2
  exit 1
fi
unset SERVER_POLICY_PRIVILEGED_SYNC_SWAP_PREPARED_INDEX
index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  [ "$(cat "$tmp/root/$relative")" = "swap-old-$index" ]
done
[ -z "$(find "$tmp/root/home/claude" -name '*.server-policy-staging-*' -print -quit)" ]

symlink_target=$tmp/root/home/claude/.codex/AGENTS.override.md
index=0
printf '%s\n' "$targets" | while IFS= read -r relative; do
  index=$((index + 1))
  printf 'preflight-%s\n' "$index" >"$tmp/root/$relative"
  chmod "$(mode_for_index "$index")" "$tmp/root/$relative"
done
backup_root=$tmp/root/var/backups/server-development-consensus
audit_log=$tmp/root/var/log/server-development-consensus/privileged-sync.jsonl
backup_count_before=$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | wc -l)
audit_lines_before=$(wc -l <"$audit_log")
rm -f "$symlink_target"
ln -s "$canonical" "$symlink_target"
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL symlinked privileged mirror was replaced' >&2
  exit 1
fi
[ -L "$symlink_target" ]
[ "$(cat "$tmp/root/etc/agent-governance/server-development-consensus.md")" = preflight-1 ]
[ "$(stat -c '%a' "$tmp/root/etc/agent-governance/server-development-consensus.md")" = 600 ]
[ "$(cat "$tmp/root/home/claude/.codex/AGENTS.md")" = preflight-2 ]
[ "$(stat -c '%a' "$tmp/root/home/claude/.codex/AGENTS.md")" = 640 ]
[ "$(cat "$tmp/root/home/claude/.claude/CLAUDE.md")" = preflight-4 ]
[ "$(stat -c '%a' "$tmp/root/home/claude/.claude/CLAUDE.md")" = 600 ]
[ "$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$backup_count_before" ]
[ "$(wc -l <"$audit_log")" = "$audit_lines_before" ]

rm -f "$symlink_target"
printf '%s\n' preflight-4 >"$symlink_target"
chmod 644 "$symlink_target"
outside=$tmp/outside
mkdir -p "$outside/agent-governance"
printf '%s\n' outside-sentinel >"$outside/agent-governance/server-development-consensus.md"
mv "$tmp/root/etc" "$tmp/root/etc.real"
ln -s "$outside" "$tmp/root/etc"
if "$sync_tool" --expected-sha256 "$expected_sha256" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL symlinked target ancestor was followed' >&2
  exit 1
fi
[ "$(cat "$outside/agent-governance/server-development-consensus.md")" = outside-sentinel ]
[ "$(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$backup_count_before" ]
[ "$(wc -l <"$audit_log")" = "$audit_lines_before" ]

printf '%s\n' 'privileged policy sync tests passed'
