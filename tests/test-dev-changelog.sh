#!/bin/sh
set -eu

# dev-changelog decides whether a repository has opted in to publishing, so the
# assertions that matter are about what it refuses to do: an unmarked repository
# is skipped, not failed, and --check reports drift without writing. These run
# against a throwaway HOME and throwaway repositories, like the other tests.

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tool=$base_dir/bin/dev-changelog
[ -x "$tool" ] || { echo "FAIL: $tool is not executable"; exit 1; }

command -v git-cliff >/dev/null 2>&1 || {
  echo "SKIP: git-cliff is not installed; dev-changelog tests need it"
  exit 0
}

export HOME=$tmp/home
mkdir -p "$HOME/.local/lib/server-development-consensus"
cp "$base_dir/lib/dev-git-common.sh" \
  "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"

make_repo() {
  repo=$1
  mkdir -p "$repo"
  git init --initial-branch=main -q "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.invalid
  for message in "feat: add alpha" "fix: repair beta" "chore: tidy the desk"; do
    printf '%s\n' "$message" >>"$repo/file.txt"
    git -C "$repo" add file.txt
    git -C "$repo" commit -q -m "$message"
  done
}

# --- an unmarked repository is skipped, never failed ------------------------
unmarked=$tmp/unmarked
make_repo "$unmarked"
if ! "$tool" --check "$unmarked" >"$tmp/unmarked.out" 2>&1; then
  echo "FAIL: --check failed an unmarked repository"
  cat "$tmp/unmarked.out"
  exit 1
fi
[ ! -e "$unmarked/CHANGELOG.md" ] || {
  echo "FAIL: --check wrote a changelog"
  exit 1
}

# --- a marked repository without a changelog is a finding -------------------
marked=$tmp/marked
make_repo "$marked"
git -C "$marked" config --local serverPolicy.publishesVersions true
if "$tool" --check "$marked" >"$tmp/missing.out" 2>&1; then
  echo "FAIL: --check passed a marked repository with no changelog"
  exit 1
fi
grep -q 'CHANGELOG.md is missing' "$tmp/missing.out" || {
  echo "FAIL: missing changelog was not reported as missing"
  cat "$tmp/missing.out"
  exit 1
}

# --- generation produces Keep a Changelog headings --------------------------
"$tool" "$marked" >/dev/null
grep -q '^# Changelog$' "$marked/CHANGELOG.md" || { echo "FAIL: no title"; exit 1; }
grep -q '^## \[Unreleased\]$' "$marked/CHANGELOG.md" || { echo "FAIL: no Unreleased section"; exit 1; }
grep -q '^### Added$' "$marked/CHANGELOG.md" || { echo "FAIL: feat not under Added"; exit 1; }
grep -q '^### Fixed$' "$marked/CHANGELOG.md" || { echo "FAIL: fix not under Fixed"; exit 1; }
grep -q 'Tidy the desk' "$marked/CHANGELOG.md" && { echo "FAIL: chore should be skipped"; exit 1; }

# --- generation is idempotent, which is what makes --check meaningful -------
if ! "$tool" --check "$marked" >/dev/null 2>&1; then
  echo "FAIL: a fresh changelog did not match its own commits"
  exit 1
fi

# --- a new commit makes the changelog stale ---------------------------------
printf 'more\n' >>"$marked/file.txt"
git -C "$marked" add file.txt
git -C "$marked" commit -q -m "feat: add omega"
if "$tool" --check "$marked" >"$tmp/drift.out" 2>&1; then
  echo "FAIL: --check passed a changelog that fell behind its commits"
  exit 1
fi
grep -q 'does not match the commits' "$tmp/drift.out" || {
  echo "FAIL: drift was not reported as drift"
  cat "$tmp/drift.out"
  exit 1
}
# --check must not repair what it reports.
grep -q 'add omega' "$marked/CHANGELOG.md" && {
  echo "FAIL: --check modified the changelog"
  exit 1
}

# --- an invalid declaration is an error, not a silent skip ------------------
broken=$tmp/broken
make_repo "$broken"
git -C "$broken" config --local serverPolicy.publishesVersions yes
if "$tool" --check "$broken" >"$tmp/broken.out" 2>&1; then
  echo "FAIL: an invalid declaration was treated as a skip"
  exit 1
fi
grep -q 'must be true or false' "$tmp/broken.out" || {
  echo "FAIL: invalid declaration was not explained"
  cat "$tmp/broken.out"
  exit 1
}

echo "dev-changelog tests passed"
