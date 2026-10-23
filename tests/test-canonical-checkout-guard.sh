#!/bin/sh
# The canonical checkout is shared by every session on this host; a commit made
# there moves HEAD under the others. This test fixes the two halves of the rule:
# a commit in the canonical checkout is refused with a message that names the
# right remedy, and a commit in a linked worktree goes through untouched.
#
# The failure this is written against is not "the hook was wrong" but "the hook
# pointed at the wrong tool": the old message said `dev-start`, which switches
# branches *in place* — the exact act the guard is meant to prevent. An agent
# that trusted it landed back in the shared checkout on a task branch.
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
hook=$base_dir/git-hooks/pre-commit
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/lib/server-development-consensus"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/git-hooks/pre-commit" "$tmp/pre-commit"
chmod +x "$tmp/pre-commit"
git config --global init.defaultBranch main

repo=$tmp/repo
git init --initial-branch=main "$repo" >/dev/null
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config serverPolicy.defaultBranch main
git -C "$repo" commit --allow-empty -m "chore: initial" >/dev/null

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

# ── A linked worktree may commit ────────────────────────────────────────────
git -C "$repo" worktree add -q "$tmp/wt" -b feat/in-worktree >/dev/null
(
  cd "$tmp/wt"
  "$tmp/pre-commit" >/dev/null 2>&1
) || fail 'pre-commit refused a commit in a linked worktree'

# ── The canonical checkout may not ──────────────────────────────────────────
# On a task branch, so the default-branch rule stays out of the way: this case
# is about *where* the commit happens, not which branch it lands on.
git -C "$repo" switch -c feat/in-canonical >/dev/null
output=$(
  cd "$repo"
  set +e
  "$tmp/pre-commit" 2>&1
  printf 'STATUS=%s\n' "$?"
)
status=$(printf '%s\n' "$output" | sed -n 's/^STATUS=//p')
[ "$status" = "1" ] || fail "pre-commit accepted a commit in the canonical checkout (status=$status)"

# ── And it must name the right remedy ───────────────────────────────────────
printf '%s\n' "$output" | grep -q 'dev-worktree start' ||
  fail 'the refusal does not tell the reader to use dev-worktree start'

# The old message recommended `dev-start`, which switches branches in place and
# is what put agents back into the shared checkout. Recommending it while
# refusing the commit would contradict the rule in the same breath.
if printf '%s\n' "$output" | grep -q 'Use: dev-start'; then
  fail 'the refusal still recommends dev-start, which switches branches in the canonical checkout'
fi

# ── The default-branch rule keeps precedence ────────────────────────────────
# A commit on `main` in the canonical checkout is both mistakes; the message
# must name the more specific one so the reader fixes the right thing first.
git -C "$repo" switch -q main
output=$(
  cd "$repo"
  set +e
  "$tmp/pre-commit" 2>&1
  printf 'STATUS=%s\n' "$?"
)
printf '%s\n' "$output" | grep -q 'commits on the default branch are prohibited' ||
  fail 'the default-branch rule no longer runs, or no longer takes precedence'

printf 'canonical checkout guard passed\n'
