#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
hook=$base_dir/git-hooks/pre-merge-commit
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/lib/server-development-consensus"
cp "$base_dir/lib/dev-git-common.sh" \
  "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"

git init --initial-branch=main "$tmp/work" >/dev/null
git -C "$tmp/work" config user.name test
git -C "$tmp/work" config user.email test@example.com
git -C "$tmp/work" config serverPolicy.defaultBranch main
printf '%s\n' initial >"$tmp/work/tracked.txt"
git -C "$tmp/work" add tracked.txt
git -C "$tmp/work" -c core.hooksPath=/dev/null commit -m initial >/dev/null
git -C "$tmp/work" switch -c feat/merge-source >/dev/null
printf '%s\n' feature >>"$tmp/work/tracked.txt"
git -C "$tmp/work" add tracked.txt
git -C "$tmp/work" -c core.hooksPath=/dev/null commit -m feature >/dev/null
git -C "$tmp/work" switch main >/dev/null
main_head=$(git -C "$tmp/work" rev-parse HEAD)
git -C "$tmp/work" config core.hooksPath "$base_dir/git-hooks"
if git -C "$tmp/work" merge --no-ff feat/merge-source -m merge \
  >"$tmp/merge.out" 2>&1; then
  printf '%s\n' 'FAIL merge commit on the default branch was allowed' >&2
  exit 1
fi
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$main_head" ]
grep -q 'commits on the default branch are prohibited' "$tmp/merge.out"
git -C "$tmp/work" merge --abort >/dev/null 2>&1 || true
git -C "$tmp/work" reset --hard "$main_head" >/dev/null

git -C "$tmp/work" switch feat/merge-source >/dev/null
git -C "$tmp/work" config serverPolicy.chainedHooksPath .project-hooks
mkdir -p "$tmp/work/.project-hooks"
printf '#!/bin/sh\nprintf chained >"%s"\n' "$tmp/chained-marker" \
  >"$tmp/work/.project-hooks/pre-merge-commit"
chmod +x "$tmp/work/.project-hooks/pre-merge-commit"
(cd "$tmp/work" && "$hook")
[ "$(cat "$tmp/chained-marker")" = chained ]

# An externally governed repository keeps its own merge process: the server
# guard is skipped while the project hook still runs, and an unreadable or
# invalid class stops the merge instead of exempting it.
git -C "$tmp/work" switch main >/dev/null
git -C "$tmp/work" config serverPolicy.repositoryClass external
rm -f "$tmp/chained-marker"
if ! (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL default-branch merge was blocked in an externally governed repository' >&2
  exit 1
fi
[ "$(cat "$tmp/chained-marker")" = chained ] || {
  printf '%s\n' 'FAIL project pre-merge-commit hook did not run for an externally governed repository' >&2
  exit 1
}
git -C "$tmp/work" config serverPolicy.repositoryClass external-governed
if (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL invalid repository class was silently exempted' >&2
  exit 1
fi

printf '%s\n' 'pre-merge-commit policy tests passed'
