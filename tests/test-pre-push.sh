#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
hook=$base_dir/git-hooks/pre-push
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export XDG_CONFIG_HOME=$HOME/.config
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/server-development-consensus"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/bin/dev-worktree" "$HOME/.local/bin/dev-worktree"
chmod +x "$HOME/.local/bin/dev-worktree"

git init --bare --initial-branch=main "$tmp/remote.git" >/dev/null
git init --bare --initial-branch=master "$tmp/upstream.git" >/dev/null
git init --initial-branch=main "$tmp/work" >/dev/null
git -C "$tmp/work" config user.name test
git -C "$tmp/work" config user.email test@example.com
git -C "$tmp/work" config serverPolicy.defaultBranch main
git -C "$tmp/work" config serverPolicy.chainedHooksPath .project-hooks
git -C "$tmp/work" remote add origin "$tmp/remote.git"
git -C "$tmp/work" remote add upstream "$tmp/upstream.git"
git -C "$tmp/work" commit --allow-empty -m initial >/dev/null
git -C "$tmp/work" push origin HEAD:main >/dev/null
git -C "$tmp/work" fetch origin main:refs/remotes/origin/main >/dev/null
git -C "$tmp/work" push upstream HEAD:master >/dev/null
git -C "$tmp/work" fetch upstream master:refs/remotes/upstream/master >/dev/null
mkdir -p "$tmp/work/.project-hooks"
printf '#!/bin/sh\nprintf "%%s\\n%%s\\n" "$1" "$2" >"%s"\ncat >"%s"\n' \
  "$tmp/chained.args" "$tmp/chained.stdin" >"$tmp/work/.project-hooks/pre-push"
chmod +x "$tmp/work/.project-hooks/pre-push"

head=$(git -C "$tmp/work" rev-parse HEAD)
zero=0000000000000000000000000000000000000000
feature_update="refs/heads/feat/test $head refs/heads/feat/test $zero"
default_update="refs/heads/main $head refs/heads/main $zero"
default_delete="(delete) $zero refs/heads/main $head"

for updates in \
  "$default_update" \
  "$default_delete" \
  "$feature_update
$default_update" \
  "$default_update
$feature_update"; do
  rm -f "$tmp/chained.args" "$tmp/chained.stdin"
  if printf '%s\n' "$updates" |
     (cd "$tmp/work" && "$hook" origin "$tmp/remote.git") >/dev/null 2>&1; then
    printf '%s\n' 'FAIL push containing the default branch was allowed' >&2
    exit 1
  fi
  [ ! -e "$tmp/chained.args" ] || {
    printf '%s\n' 'FAIL project hook ran for a blocked default-branch push' >&2
    exit 1
  }
done

printf '%s\n' "$feature_update" |
  (cd "$tmp/work" && "$hook" origin "$tmp/remote.git")
[ "$(sed -n '1p' "$tmp/chained.args")" = origin ]
[ "$(sed -n '2p' "$tmp/chained.args")" = "$tmp/remote.git" ]
[ "$(cat "$tmp/chained.stdin")" = "$feature_update" ] || {
  printf '%s\n' 'FAIL project pre-push hook did not receive the original stdin' >&2
  exit 1
}

git -C "$tmp/work" worktree add --no-track -b feat/dirty-sibling \
  "$tmp/dirty-sibling" origin/main >/dev/null
printf '%s\n' dirty >"$tmp/dirty-sibling/overlap.txt"
git -C "$tmp/work" switch -c feat/overlap >/dev/null
printf '%s\n' committed >"$tmp/work/overlap.txt"
git -C "$tmp/work" add overlap.txt
git -C "$tmp/work" commit -m overlap >/dev/null
overlap_head=$(git -C "$tmp/work" rev-parse HEAD)
overlap_update="refs/heads/feat/overlap $overlap_head refs/heads/feat/overlap $zero"
rm -f "$tmp/chained.args" "$tmp/chained.stdin"
if printf '%s\n' "$overlap_update" |
   (cd "$tmp/work" && "$hook" origin "$tmp/remote.git") \
     >"$tmp/overlap.out" 2>&1; then
  printf '%s\n' 'FAIL push overlapping a dirty sibling worktree was allowed' >&2
  exit 1
fi
grep -q 'overlap.txt' "$tmp/overlap.out"
[ ! -e "$tmp/chained.args" ] || {
  printf '%s\n' 'FAIL chained hook ran for a worktree-overlap rejection' >&2
  exit 1
}
rm -f "$tmp/dirty-sibling/overlap.txt"
git -C "$tmp/work" worktree remove "$tmp/dirty-sibling"
git -C "$tmp/work" branch -D feat/dirty-sibling >/dev/null
git -C "$tmp/work" switch main >/dev/null

if printf 'refs/heads/master %s refs/heads/master %s\n' "$head" "$zero" |
   (cd "$tmp/work" && "$hook" upstream "$tmp/upstream.git") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL second remote default branch push was allowed' >&2
  exit 1
fi

git -C "$tmp/work" remote set-url --push origin "$tmp/upstream.git"
if printf 'refs/heads/master %s refs/heads/master %s\n' "$head" "$zero" |
   (cd "$tmp/work" && "$hook" origin "$tmp/upstream.git") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL push URL default branch bypassed origin fetch metadata' >&2
  exit 1
fi
git -C "$tmp/work" remote set-url --push origin "$tmp/remote.git"

if printf 'refs/heads/master %s refs/heads/master %s\n' "$head" "$zero" |
   (cd "$tmp/work" && "$hook" "$tmp/upstream.git" "$tmp/upstream.git") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL direct URL push bypassed named-remote validation' >&2
  exit 1
fi

printf '#!/bin/sh\ncat >/dev/null\nexit 42\n' >"$tmp/work/.project-hooks/pre-push"
set +e
printf '%s\n' "$feature_update" |
  (cd "$tmp/work" && "$hook" origin "$tmp/remote.git") >/dev/null 2>&1
hook_status=$?
set -e
[ "$hook_status" -eq 42 ] || {
  printf 'FAIL project pre-push failure was not propagated: %s\n' "$hook_status" >&2
  exit 1
}

mkdir -p "$tmp/work/.hardlink-hooks"
ln "$hook" "$tmp/work/.hardlink-hooks/pre-push"
git -C "$tmp/work" config serverPolicy.chainedHooksPath .hardlink-hooks
if printf '%s\n' "$feature_update" |
   (cd "$tmp/work" && "$hook" origin "$tmp/remote.git") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL hard-linked managed pre-push hook was accepted as a chain' >&2
  exit 1
fi

printf '%s\n' 'pre-push policy tests passed'
