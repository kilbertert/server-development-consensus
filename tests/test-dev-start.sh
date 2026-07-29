#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/lib/server-development-consensus" "$HOME/.local/bin"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/bin/dev-start" "$HOME/.local/bin/dev-start"
chmod +x "$HOME/.local/bin/dev-start"

git init --bare --initial-branch=main "$tmp/remote.git" >/dev/null
git init --initial-branch=main "$tmp/seed" >/dev/null
git -C "$tmp/seed" config user.name test
git -C "$tmp/seed" config user.email test@example.com
printf '%s\n' initial >"$tmp/seed/tracked.txt"
git -C "$tmp/seed" add tracked.txt
git -C "$tmp/seed" commit -m initial >/dev/null
git -C "$tmp/seed" remote add origin "$tmp/remote.git"
git -C "$tmp/seed" push -u origin main >/dev/null

git clone "$tmp/remote.git" "$tmp/clean" >/dev/null 2>&1
git -C "$tmp/clean" config serverPolicy.defaultBranch main
git -C "$tmp/clean" config --unset-all remote.origin.fetch
git -C "$tmp/clean" config --add remote.origin.fetch \
  '+refs/heads/unused:refs/remotes/origin/unused'
printf '%s\n' remote-update >"$tmp/seed/remote-update.txt"
git -C "$tmp/seed" add remote-update.txt
git -C "$tmp/seed" commit -m remote-update >/dev/null
git -C "$tmp/seed" push >/dev/null
(cd "$tmp/clean" && "$HOME/.local/bin/dev-start" feat clean-flow >/dev/null)
[ "$(git -C "$tmp/clean" branch --show-current)" = feat/clean-flow ]
[ "$(cat "$tmp/clean/remote-update.txt")" = remote-update ]

git clone "$tmp/remote.git" "$tmp/dirty" >/dev/null 2>&1
git -C "$tmp/dirty" config serverPolicy.defaultBranch main
printf '%s\n' staged >"$tmp/dirty/tracked.txt"
git -C "$tmp/dirty" add tracked.txt
printf '%s\n' unstaged >>"$tmp/dirty/tracked.txt"
printf '%s\n' untracked >"$tmp/dirty/untracked.txt"
(cd "$tmp/dirty" && "$HOME/.local/bin/dev-start" fix preserve-work >/dev/null)
[ "$(git -C "$tmp/dirty" branch --show-current)" = fix/preserve-work ]
[ "$(git -C "$tmp/dirty" show :tracked.txt)" = staged ]
[ "$(tail -n 1 "$tmp/dirty/tracked.txt")" = unstaged ]
[ "$(cat "$tmp/dirty/untracked.txt")" = untracked ]
[ -n "$(git -C "$tmp/dirty" status --porcelain)" ]

git clone "$tmp/remote.git" "$tmp/dirty-hook-failure" >/dev/null 2>&1
git -C "$tmp/dirty-hook-failure" config serverPolicy.defaultBranch main
printf '%s\n' staged >"$tmp/dirty-hook-failure/tracked.txt"
git -C "$tmp/dirty-hook-failure" add tracked.txt
printf '%s\n' unstaged >>"$tmp/dirty-hook-failure/tracked.txt"
printf '%s\n' untracked >"$tmp/dirty-hook-failure/untracked.txt"
printf '%s\n' \
  '#!/bin/sh' \
  '[ "$(git branch --show-current)" != fix/dirty-hook-failure ]' \
  >"$tmp/dirty-hook-failure/.git/hooks/post-checkout"
chmod +x "$tmp/dirty-hook-failure/.git/hooks/post-checkout"
dirty_head=$(git -C "$tmp/dirty-hook-failure" rev-parse HEAD)
dirty_status=$(git -C "$tmp/dirty-hook-failure" status --porcelain=v1)
if (cd "$tmp/dirty-hook-failure" && \
    "$HOME/.local/bin/dev-start" fix dirty-hook-failure) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL dirty task start ignored a failed post-checkout hook' >&2
  exit 1
fi
[ "$(git -C "$tmp/dirty-hook-failure" branch --show-current)" = main ]
[ "$(git -C "$tmp/dirty-hook-failure" rev-parse HEAD)" = "$dirty_head" ]
[ "$(git -C "$tmp/dirty-hook-failure" status --porcelain=v1)" = "$dirty_status" ]
[ "$(git -C "$tmp/dirty-hook-failure" show :tracked.txt)" = staged ]
[ "$(tail -n 1 "$tmp/dirty-hook-failure/tracked.txt")" = unstaged ]
[ "$(cat "$tmp/dirty-hook-failure/untracked.txt")" = untracked ]
! git -C "$tmp/dirty-hook-failure" show-ref --verify --quiet \
  refs/heads/fix/dirty-hook-failure

git clone "$tmp/remote.git" "$tmp/dirty-ahead" >/dev/null 2>&1
git -C "$tmp/dirty-ahead" config user.name test
git -C "$tmp/dirty-ahead" config user.email test@example.com
git -C "$tmp/dirty-ahead" config serverPolicy.defaultBranch main
git -C "$tmp/dirty-ahead" commit --allow-empty -m local-only >/dev/null
printf '%s\n' dirty >"$tmp/dirty-ahead/dirty.txt"
dirty_ahead_head=$(git -C "$tmp/dirty-ahead" rev-parse HEAD)
if (cd "$tmp/dirty-ahead" && \
    "$HOME/.local/bin/dev-start" fix reject-dirty-ahead) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL dirty task branch inherited local-only default commits' >&2
  exit 1
fi
[ "$(git -C "$tmp/dirty-ahead" branch --show-current)" = main ]
[ "$(git -C "$tmp/dirty-ahead" rev-parse HEAD)" = "$dirty_ahead_head" ]
[ "$(cat "$tmp/dirty-ahead/dirty.txt")" = dirty ]
! git -C "$tmp/dirty-ahead" show-ref --verify --quiet \
  refs/heads/fix/reject-dirty-ahead

git clone "$tmp/remote.git" "$tmp/missing-default" >/dev/null 2>&1
git -C "$tmp/missing-default" config serverPolicy.defaultBranch main
git -C "$tmp/missing-default" switch -c feat/current >/dev/null
git -C "$tmp/missing-default" branch -D main >/dev/null
(cd "$tmp/missing-default" && "$HOME/.local/bin/dev-start" feat recreate-default >/dev/null)
[ "$(git -C "$tmp/missing-default" branch --show-current)" = feat/recreate-default ]
[ "$(git -C "$tmp/missing-default" rev-parse main)" = \
  "$(git -C "$tmp/missing-default" rev-parse origin/main)" ]

git clone "$tmp/remote.git" "$tmp/restore-context" >/dev/null 2>&1
git -C "$tmp/restore-context" config serverPolicy.defaultBranch main
git -C "$tmp/restore-context" switch -c feat/current >/dev/null
printf '%s\n' \
  '#!/bin/sh' \
  'branch=$(git branch --show-current)' \
  '[ "$branch" != chore/restore-context ]' \
  >"$tmp/restore-context/.git/hooks/post-checkout"
chmod +x "$tmp/restore-context/.git/hooks/post-checkout"
restore_head=$(git -C "$tmp/restore-context" rev-parse HEAD)
if (cd "$tmp/restore-context" && \
    "$HOME/.local/bin/dev-start" chore restore-context) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL task start ignored a failed final branch switch' >&2
  exit 1
fi
[ "$(git -C "$tmp/restore-context" branch --show-current)" = feat/current ]
[ "$(git -C "$tmp/restore-context" rev-parse HEAD)" = "$restore_head" ]
! git -C "$tmp/restore-context" show-ref --verify --quiet refs/heads/chore/restore-context

git clone "$tmp/remote.git" "$tmp/race-owner" >/dev/null 2>&1
git -C "$tmp/race-owner" config user.name test
git -C "$tmp/race-owner" config user.email test@example.com
git -C "$tmp/race-owner" config serverPolicy.defaultBranch main
git -C "$tmp/race-owner" switch -c feat/current >/dev/null
race_tree=$(git -C "$tmp/race-owner" rev-parse HEAD^{tree})
race_parent=$(git -C "$tmp/race-owner" rev-parse HEAD)
race_commit=$(printf '%s\n' race |
  git -C "$tmp/race-owner" commit-tree "$race_tree" -p "$race_parent")
real_git=$(command -v git)
mkdir -p "$tmp/race-bin"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "${DEV_START_RACE_ARMED:-}" = 1 ] && [ "$1 $2" = "switch main" ]; then' \
  '  "$REAL_GIT" "$@" || exit $?' \
  '  "$REAL_GIT" branch "$DEV_START_RACE_BRANCH" "$DEV_START_RACE_COMMIT"' \
  '  exit 0' \
  'fi' \
  'exec "$REAL_GIT" "$@"' >"$tmp/race-bin/git"
chmod +x "$tmp/race-bin/git"
if (cd "$tmp/race-owner" && env \
    REAL_GIT="$real_git" DEV_START_RACE_ARMED=1 \
    DEV_START_RACE_BRANCH=fix/concurrent-owner DEV_START_RACE_COMMIT="$race_commit" \
    PATH="$tmp/race-bin:$PATH" \
    "$HOME/.local/bin/dev-start" fix concurrent-owner) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL task start ignored a concurrently created branch' >&2
  exit 1
fi
[ "$(git -C "$tmp/race-owner" branch --show-current)" = feat/current ]
[ "$(git -C "$tmp/race-owner" rev-parse fix/concurrent-owner)" = "$race_commit" ]

git clone "$tmp/remote.git" "$tmp/ahead" >/dev/null 2>&1
git -C "$tmp/ahead" config user.name test
git -C "$tmp/ahead" config user.email test@example.com
git -C "$tmp/ahead" config serverPolicy.defaultBranch main
git -C "$tmp/ahead" commit --allow-empty -m local-only >/dev/null
ahead_head=$(git -C "$tmp/ahead" rev-parse HEAD)
git -C "$tmp/ahead" switch -c feat/current origin/main >/dev/null
current_head=$(git -C "$tmp/ahead" rev-parse HEAD)
if (cd "$tmp/ahead" && "$HOME/.local/bin/dev-start" chore reject-ahead) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL task branch inherited local-only default-branch commits' >&2
  exit 1
fi
[ "$(git -C "$tmp/ahead" branch --show-current)" = feat/current ]
[ "$(git -C "$tmp/ahead" rev-parse HEAD)" = "$current_head" ]
[ "$(git -C "$tmp/ahead" rev-parse main)" = "$ahead_head" ]
! git -C "$tmp/ahead" show-ref --verify --quiet refs/heads/chore/reject-ahead

git -C "$tmp/seed" commit --allow-empty -m remote-divergence >/dev/null
git -C "$tmp/seed" push >/dev/null
if (cd "$tmp/ahead" && "$HOME/.local/bin/dev-start" chore reject-diverged) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL task start accepted a diverged local default branch' >&2
  exit 1
fi
[ "$(git -C "$tmp/ahead" branch --show-current)" = feat/current ]
[ "$(git -C "$tmp/ahead" rev-parse HEAD)" = "$current_head" ]
! git -C "$tmp/ahead" show-ref --verify --quiet refs/heads/chore/reject-diverged

git -C "$tmp/seed" switch -c feat/existing >/dev/null
git -C "$tmp/seed" push -u origin feat/existing >/dev/null
git clone "$tmp/remote.git" "$tmp/collision" >/dev/null 2>&1
git -C "$tmp/collision" config serverPolicy.defaultBranch main
git -C "$tmp/collision" update-ref -d refs/remotes/origin/feat/existing
if (cd "$tmp/collision" && "$HOME/.local/bin/dev-start" feat existing) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL stale local refs hid an existing remote task branch' >&2
  exit 1
fi
[ "$(git -C "$tmp/collision" branch --show-current)" = main ]
! git -C "$tmp/collision" show-ref --verify --quiet refs/heads/feat/existing

printf '%s\n' 'dev-start workflow tests passed'
