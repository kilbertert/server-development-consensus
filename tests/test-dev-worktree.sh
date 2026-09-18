#!/usr/bin/env bash
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

git init --bare --initial-branch=main "$tmp/remote.git" >/dev/null
git init --initial-branch=main "$tmp/seed" >/dev/null
git -C "$tmp/seed" config user.name test
git -C "$tmp/seed" config user.email test@example.com
printf '%s\n' base >"$tmp/seed/shared.txt"
printf '%s\n' base >"$tmp/seed/main.txt"
git -C "$tmp/seed" add shared.txt main.txt
git -C "$tmp/seed" commit -m initial >/dev/null
git -C "$tmp/seed" remote add origin "$tmp/remote.git"
git -C "$tmp/seed" push origin main >/dev/null

git clone "$tmp/remote.git" "$HOME/Projects/repo" >/dev/null 2>&1
git -C "$HOME/Projects/repo" config user.name test
git -C "$HOME/Projects/repo" config user.email test@example.com
git -C "$HOME/Projects/repo" config serverPolicy.defaultBranch main
base_oid=$(git -C "$HOME/Projects/repo" rev-parse origin/main)

(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" start feat lifecycle
)
[ -d "$HOME/Projects/.worktrees/repo-lifecycle" ]
[ "$(git -C "$HOME/Projects/.worktrees/repo-lifecycle" branch --show-current)" = feat/lifecycle ]
[ -z "$(git -C "$HOME/Projects/repo" for-each-ref --format='%(upstream:short)' refs/heads/feat/lifecycle)" ]
[ "$(git -C "$HOME/Projects/repo" config --get branch.feat/lifecycle.serverPolicyBaseOid)" = "$base_oid" ]
[ "$(git -C "$HOME/Projects/repo" config --get branch.feat/lifecycle.serverPolicyState)" = active ]
(cd "$HOME/Projects/repo" && "$HOME/.local/bin/dev-worktree" audit) >/dev/null

if (cd "$HOME/Projects/repo" &&
    "$HOME/.local/bin/dev-worktree" start feat topbad "$HOME/Projects/repo-topbad") \
  >"$tmp/topbad.out" 2>&1; then
  printf '%s\n' 'FAIL top-level task worktree path was accepted' >&2
  exit 1
fi
grep -q 'Workspace Layout' "$tmp/topbad.out"
[ ! -e "$HOME/Projects/repo-topbad" ]
(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" start feat inrepo "$HOME/Projects/repo/.worktrees/feat-inrepo"
) >/dev/null
[ "$(git -C "$HOME/Projects/repo/.worktrees/feat-inrepo" branch --show-current)" = feat/inrepo ]

printf '%s\n' dirty >"$HOME/Projects/.worktrees/repo-lifecycle/shared.txt"
git -C "$HOME/Projects/repo" switch -c fix/competing >/dev/null
printf '%s\n' competing >"$HOME/Projects/repo/shared.txt"
git -C "$HOME/Projects/repo" add shared.txt
git -C "$HOME/Projects/repo" commit -m competing >/dev/null
set +e
overlap_output=$(
  cd "$HOME/Projects/repo" &&
    "$HOME/.local/bin/dev-worktree" guard-overlap \
      --tip HEAD --default origin/main 2>&1
)
overlap_status=$?
set -e
[ "$overlap_status" -eq 3 ] || {
  printf 'FAIL overlapping dirty worktree was not rejected: %s\n' "$overlap_status" >&2
  exit 1
}
grep -q 'path=shared.txt' <<<"$overlap_output"

git -C "$HOME/Projects/repo" switch main >/dev/null
git -C "$HOME/Projects/repo" switch -c docs/nonoverlap >/dev/null
printf '%s\n' independent >"$HOME/Projects/repo/independent.txt"
git -C "$HOME/Projects/repo" add independent.txt
git -C "$HOME/Projects/repo" commit -m independent >/dev/null
(
  cd "$HOME/Projects/repo"
  GIT_DIR=$(git rev-parse --absolute-git-dir) \
    "$HOME/.local/bin/dev-worktree" guard-overlap --tip HEAD --default origin/main
)

printf '%s\n' advanced >"$tmp/seed/main.txt"
git -C "$tmp/seed" add main.txt
git -C "$tmp/seed" commit -m advance >/dev/null
git -C "$tmp/seed" push origin main >/dev/null
git -C "$HOME/Projects/repo" fetch origin main:refs/remotes/origin/main >/dev/null
if (cd "$HOME/Projects/repo" && "$HOME/.local/bin/dev-worktree" audit) \
  >"$tmp/audit-behind.out" 2>&1; then
  printf '%s\n' 'FAIL uncommitted-only-behind worktree passed audit' >&2
  exit 1
fi
grep -q 'state=uncommitted_only_behind' "$tmp/audit-behind.out"

(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" preserve \
    "$HOME/Projects/.worktrees/repo-lifecycle" 'user-owned paused work'
  "$HOME/.local/bin/dev-worktree" audit
) >/dev/null
(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" activate "$HOME/Projects/.worktrees/repo-lifecycle"
) >/dev/null

git -C "$HOME/Projects/.worktrees/repo-lifecycle" restore shared.txt
printf '%s\n' delivered >"$HOME/Projects/.worktrees/repo-lifecycle/feature.txt"
git -C "$HOME/Projects/.worktrees/repo-lifecycle" add feature.txt
git -C "$HOME/Projects/.worktrees/repo-lifecycle" commit -m feature >/dev/null
git -C "$HOME/Projects/.worktrees/repo-lifecycle" push origin HEAD:refs/heads/feat/lifecycle >/dev/null
git -C "$tmp/seed" fetch origin feat/lifecycle >/dev/null
git -C "$tmp/seed" cherry-pick origin/feat/lifecycle >/dev/null
git -C "$tmp/seed" push origin main >/dev/null
git -C "$HOME/Projects/repo" fetch --prune origin >/dev/null
(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" retire "$HOME/Projects/.worktrees/repo-lifecycle"
) >/dev/null
[ ! -e "$HOME/Projects/.worktrees/repo-lifecycle" ]
! git -C "$HOME/Projects/repo" show-ref --verify --quiet refs/heads/feat/lifecycle

(
  cd "$HOME/Projects/repo"
  "$HOME/.local/bin/dev-worktree" start feat squash
) >/dev/null
printf '%s\n' one >"$HOME/Projects/.worktrees/repo-squash/squash-one.txt"
git -C "$HOME/Projects/.worktrees/repo-squash" add squash-one.txt
git -C "$HOME/Projects/.worktrees/repo-squash" commit -m squash-one >/dev/null
printf '%s\n' two >"$HOME/Projects/.worktrees/repo-squash/squash-two.txt"
git -C "$HOME/Projects/.worktrees/repo-squash" add squash-two.txt
git -C "$HOME/Projects/.worktrees/repo-squash" commit -m squash-two >/dev/null
squash_head=$(git -C "$HOME/Projects/.worktrees/repo-squash" rev-parse HEAD)
git -C "$HOME/Projects/.worktrees/repo-squash" push origin HEAD:refs/heads/feat/squash >/dev/null
git -C "$tmp/seed" fetch origin feat/squash >/dev/null
git -C "$tmp/seed" merge --squash origin/feat/squash >/dev/null
git -C "$tmp/seed" commit -m squash-merge >/dev/null
squash_merge=$(git -C "$tmp/seed" rev-parse HEAD)
git -C "$tmp/seed" push origin main >/dev/null
git -C "$HOME/Projects/repo" fetch --prune origin >/dev/null
git -C "$HOME/Projects/repo" cherry origin/main feat/squash | grep -q '^+'
cat >"$HOME/.local/bin/gh" <<EOF
#!/bin/sh
printf '%s\t%s\t%s\n' 42 https://example.test/pull/42 $squash_merge
EOF
chmod +x "$HOME/.local/bin/gh"
retire_output=$(
  cd "$HOME/Projects/repo" &&
    "$HOME/.local/bin/dev-worktree" retire "$HOME/Projects/.worktrees/repo-squash"
)
grep -q 'verification=pr#42' <<<"$retire_output"
grep -q "merge=$squash_merge" <<<"$retire_output"
[ "$squash_head" != "$squash_merge" ]
rm "$HOME/.local/bin/gh"

git -C "$HOME/Projects/repo" worktree add -b fix/tracks-default \
  "$HOME/Projects/.worktrees/repo-tracks-default" origin/main >/dev/null
if (cd "$HOME/Projects/repo" && "$HOME/.local/bin/dev-worktree" audit) \
  >"$tmp/audit-tracking.out" 2>&1; then
  printf '%s\n' 'FAIL task worktree tracking origin/main passed audit' >&2
  exit 1
fi
grep -q 'state=tracks_default' "$tmp/audit-tracking.out"

# An externally governed repository keeps its own delivery process: the server
# task lifecycle refuses to act on it and the delivery audit no longer fails
# it, while the workspace worktree location rule still reports it.
git -C "$HOME/Projects/repo" worktree add --detach "$tmp/outside" origin/main \
  >/dev/null
git -C "$HOME/Projects/repo" config serverPolicy.repositoryClass external
external_audit=$(
  cd "$HOME/Projects/repo" && "$HOME/.local/bin/dev-worktree" audit
)
grep -q 'state=tracks_default' <<<"$external_audit"
grep -q 'location=violation' <<<"$external_audit"
if (cd "$HOME/Projects/repo" &&
    "$HOME/.local/bin/dev-worktree" start feat external) >"$tmp/external-start.out" 2>&1; then
  printf '%s\n' 'FAIL dev-worktree start ran in an externally governed repository' >&2
  exit 1
fi
grep -q 'externally governed' "$tmp/external-start.out"
if (cd "$HOME/Projects/repo" &&
    "$HOME/.local/bin/dev-worktree" retire "$HOME/Projects/.worktrees/repo-tracks-default") \
  >"$tmp/external-retire.out" 2>&1; then
  printf '%s\n' 'FAIL dev-worktree retire ran in an externally governed repository' >&2
  exit 1
fi
grep -q 'externally governed' "$tmp/external-retire.out"
git -C "$HOME/Projects/repo" config --unset serverPolicy.repositoryClass

printf '%s\n' 'dev-worktree lifecycle tests passed'
