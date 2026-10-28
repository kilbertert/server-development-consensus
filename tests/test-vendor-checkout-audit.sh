#!/usr/bin/env bash
# A checkout pinned to a tag, living at a path its enclosing repository
# ignores, is a vendored dependency - not a delivery surface. The audit must
# report it and pass, and it must not blind the audit to the repository's real
# worktrees.
set -euo pipefail

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export XDG_CONFIG_HOME=$HOME/.config
export GIT_CONFIG_NOSYSTEM=1
export PATH="$HOME/.local/bin:$PATH"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/server-development-consensus" \
  "$HOME/Projects"
cp "$base_dir/lib/dev-git-common.sh" \
  "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/bin/dev-worktree" "$HOME/.local/bin/dev-worktree"
chmod +x "$HOME/.local/bin/dev-worktree"

worktree=$HOME/.local/bin/dev-worktree

git init --bare --initial-branch=main "$tmp/remote.git" >/dev/null
git init --initial-branch=main "$tmp/seed" >/dev/null
git -C "$tmp/seed" config user.name test
git -C "$tmp/seed" config user.email test@example.com
printf '%s\n' base >"$tmp/seed/file.txt"
git -C "$tmp/seed" add file.txt
git -C "$tmp/seed" commit -m initial >/dev/null
git -C "$tmp/seed" tag v1.0
git -C "$tmp/seed" remote add origin "$tmp/remote.git"
git -C "$tmp/seed" push origin main >/dev/null

git clone "$tmp/remote.git" "$HOME/Projects/repo" >/dev/null 2>&1
git -C "$HOME/Projects/repo" config user.name test
git -C "$HOME/Projects/repo" config user.email test@example.com
git -C "$HOME/Projects/repo" config serverPolicy.defaultBranch main

# 1. A vendored, tag-pinned checkout at an ignored path: reported, not a failure.
mkdir -p "$HOME/Projects/repo/deploy/web-patches/work"
printf '%s\n' 'deploy/web-patches/work/' >"$HOME/Projects/repo/.gitignore"
git -C "$HOME/Projects/repo" add .gitignore
git -C "$HOME/Projects/repo" commit -m 'ignore vendor tree' >/dev/null
git -C "$HOME/Projects/repo" push origin main >/dev/null
git init -q --initial-branch=main "$tmp/dep-seed"
git -C "$tmp/dep-seed" config user.name test
git -C "$tmp/dep-seed" config user.email test@example.com
printf '%s\n' dep >"$tmp/dep-seed/dep.txt"
git -C "$tmp/dep-seed" add dep.txt
git -C "$tmp/dep-seed" commit -m dep >/dev/null
git -C "$tmp/dep-seed" tag dep-v1
git clone -q --no-checkout "$tmp/dep-seed" "$HOME/Projects/repo/deploy/web-patches/work"
git -C "$HOME/Projects/repo/deploy/web-patches/work" checkout -q dep-v1

# The audit runs from inside the enclosing repository. `git worktree list`
# never reports a nested independent clone, so the vendored tree is not walked
# here: what must hold is that its presence changes nothing for the repository
# the audit is actually about.
(
  cd "$HOME/Projects/repo"
  "$worktree" audit
) >"$tmp/vendor.out" 2>&1 || true
grep -q 'worktree audit passed' "$tmp/vendor.out"
if grep -q 'default branch reference is unavailable' "$tmp/vendor.out"; then
  printf '%s\n' 'FAIL vendored checkout aborted the audit' >&2
  exit 1
fi

# 2. Discovery drops the vendored tree and keeps the enclosing repository. This
# is the layer that matters: without it the policy audit attributes the managed
# lifecycle to the dependency and fails on it.
(
  cd "$HOME/Projects/repo"
  . "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
  find_project_git_entries "$HOME/Projects" >"$tmp/entries"
)
if grep -q 'repo/deploy/web-patches/work' "$tmp/entries"; then
  printf '%s\n' 'FAIL vendored checkout survived discovery' >&2
  exit 1
fi
grep -q 'repo/.git' "$tmp/entries"

# 2. A real task worktree in the same repository is still audited as one: the
# vendor tree must not have disabled the lifecycle rules for the whole repo.
(
  cd "$HOME/Projects/repo"
  "$worktree" start feat realwork
) >/dev/null
(
  cd "$HOME/Projects/.worktrees/repo-realwork"
  "$worktree" audit
) >"$tmp/stray.out" 2>&1 || true
grep -q 'branch=feat/realwork' "$tmp/stray.out"
if grep -q 'state=vendor-checkout' "$tmp/stray.out"; then
  printf '%s\n' 'FAIL vendor tree was attributed to the repository worktree audit' >&2
  exit 1
fi

# 3. A tag-pinned checkout with no default branch is reported as a vendor
# checkout rather than aborting: `dev-worktree audit --repo <path>` on such a
# checkout must not die with "default branch reference is unavailable", which
# used to take the whole audit of the enclosing repository down with it.
(
  cd "$HOME/Projects/repo/deploy/web-patches/work"
  "$worktree" audit
) >"$tmp/pinned.out" 2>&1 || true
grep -q 'state=vendor-checkout' "$tmp/pinned.out"
if grep -q 'default branch reference is unavailable' "$tmp/pinned.out"; then
  printf '%s\n' 'FAIL pinned checkout died on the missing default ref' >&2
  exit 1
fi

printf '%s\n' 'vendor checkout audit: ok'
