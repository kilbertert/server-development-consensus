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

# The generator is only meaningful with git-cliff present, so its absence is a
# failure rather than a skip: a suite that silently skips in CI verifies nothing
# while still reporting success. CI installs it explicitly.
command -v git-cliff >/dev/null 2>&1 || {
  echo "FAIL: git-cliff is not installed; the generator cannot be verified"
  exit 1
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

# --- an empty value is a malformed declaration, not an absent one -----------
empty=$tmp/empty
make_repo "$empty"
git -C "$empty" config --local serverPolicy.publishesVersions ''
if "$tool" --check "$empty" >"$tmp/empty.out" 2>&1; then
  echo "FAIL: an empty declaration was treated as a skip"
  exit 1
fi
grep -q 'must be true or false' "$tmp/empty.out" || {
  echo "FAIL: empty declaration was not explained"
  cat "$tmp/empty.out"
  exit 1
}

# --- a bare MAJOR.MINOR.PATCH tag is a version boundary ---------------------
# The policy specifies annotated SemVer tags without a prefix, so the tag
# pattern has to accept `1.2.0` as well as `v1.2.0`; a pattern that only
# accepted one of them would fold a real release into Unreleased.
tagged=$tmp/tagged
make_repo "$tagged"
git -C "$tagged" config --local serverPolicy.publishesVersions true
git -C "$tagged" tag -a 1.0.0 -m "release 1.0.0"
printf 'more\n' >>"$tagged/file.txt"
git -C "$tagged" add file.txt
git -C "$tagged" commit -q -m "feat: after the release"
"$tool" "$tagged" >/dev/null
grep -q '^## \[1\.0\.0\]' "$tagged/CHANGELOG.md" || {
  echo "FAIL: a bare version tag did not produce a version section"
  cat "$tagged/CHANGELOG.md"
  exit 1
}
# The commit after the tag belongs to Unreleased, not to the released section.
grep -q '^## \[Unreleased\]$' "$tagged/CHANGELOG.md" || { echo "FAIL: no Unreleased"; exit 1; }
awk '/^## \[Unreleased\]/{u=1} /^## \[1\.0\.0\]/{u=0} u' "$tagged/CHANGELOG.md" |
  grep -q 'After the release' || { echo "FAIL: post-tag commit not under Unreleased"; exit 1; }

# --- an explicit subdirectory argument still targets the repository root ----
# `git -C` accepts any directory in the work tree, so rendering beside the
# argument would let one repository hold two different changelogs.
mkdir -p "$tagged/sub"
"$tool" "$tagged/sub" >/dev/null
[ ! -e "$tagged/sub/CHANGELOG.md" ] || {
  echo "FAIL: a subdirectory argument wrote a changelog below the root"
  exit 1
}
if ! "$tool" --check "$tagged/sub" >/dev/null 2>&1; then
  echo "FAIL: a subdirectory argument did not check the root changelog"
  exit 1
fi

echo "dev-changelog tests passed"
