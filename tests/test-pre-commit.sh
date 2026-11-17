#!/bin/sh
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
git config --global init.defaultBranch main

git init --initial-branch=main "$tmp/work" >/dev/null
git -C "$tmp/work" config user.name test
git -C "$tmp/work" config user.email test@example.com
git -C "$tmp/work" config serverPolicy.defaultBranch main
git -C "$tmp/work" config serverPolicy.chainedHooksPath .project-hooks
mkdir -p "$tmp/work/.project-hooks"
printf '#!/bin/sh\nprintf chained >"%s"\n' "$tmp/chained-marker" >"$tmp/work/.project-hooks/pre-commit"
chmod +x "$tmp/work/.project-hooks/pre-commit"

if (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL initial commit on the default branch was allowed' >&2
  exit 1
fi
[ ! -e "$tmp/chained-marker" ] || {
  printf '%s\n' 'FAIL project hook ran for a blocked initial commit' >&2
  exit 1
}

git -C "$tmp/work" -c core.hooksPath=/dev/null commit --allow-empty -m initial >/dev/null
if (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL commit on the default branch was allowed' >&2
  exit 1
fi
[ ! -e "$tmp/chained-marker" ] || {
  printf '%s\n' 'FAIL project hook ran for a blocked default-branch commit' >&2
  exit 1
}

git -C "$tmp/work" config serverPolicy.defaultBranch develop
if (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL valid but incorrect default-branch metadata was trusted' >&2
  exit 1
fi
git -C "$tmp/work" config serverPolicy.defaultBranch main

# Task work happens in a linked worktree, never in the canonical checkout:
# the pre-commit guard refuses commits made in the shared one (2026-10-23).
git -C "$tmp/work" worktree add -q "$tmp/wt" -b feat/test >/dev/null
mkdir -p "$tmp/wt/.project-hooks"
printf '#!/bin/sh\nprintf chained >"%s"\n' "$tmp/chained-marker" >"$tmp/wt/.project-hooks/pre-commit"
chmod +x "$tmp/wt/.project-hooks/pre-commit"
rm -f "$tmp/chained-marker"
(cd "$tmp/wt" && "$hook")
[ "$(cat "$tmp/chained-marker")" = chained ] || {
  printf '%s\n' 'FAIL project pre-commit hook was not chained' >&2
  exit 1
}

printf '#!/bin/sh\nexit 42\n' >"$tmp/wt/.project-hooks/pre-commit"
set +e
(cd "$tmp/wt" && "$hook") >/dev/null 2>&1
hook_status=$?
set -e
[ "$hook_status" -eq 42 ] || {
  printf 'FAIL project pre-commit failure was not propagated: %s\n' "$hook_status" >&2
  exit 1
}

git -C "$tmp/work" config serverPolicy.defaultBranch '@{-1}'
if (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL non-canonical default-branch metadata was accepted' >&2
  exit 1
fi
git -C "$tmp/work" config serverPolicy.defaultBranch main

mkdir -p "$tmp/wt/.hardlink-hooks"
ln "$hook" "$tmp/wt/.hardlink-hooks/pre-commit"
git -C "$tmp/work" config serverPolicy.chainedHooksPath .hardlink-hooks
if (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL hard-linked managed pre-commit hook was accepted as a chain' >&2
  exit 1
fi

git -C "$tmp/work" config serverPolicy.chainedHooksPath "$base_dir/git-hooks"
if (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL self-referential pre-commit chain was accepted' >&2
  exit 1
fi

# An externally governed repository keeps its own default-branch process: the
# server guard is skipped while the project hook still runs, and an unreadable
# or invalid class stops the commit instead of exempting it.
git -C "$tmp/work" switch main >/dev/null
git -C "$tmp/work" config serverPolicy.chainedHooksPath .project-hooks
printf '#!/bin/sh\nprintf chained >"%s"\n' "$tmp/chained-marker" \
  >"$tmp/wt/.project-hooks/pre-commit"
chmod +x "$tmp/wt/.project-hooks/pre-commit"
git -C "$tmp/work" config serverPolicy.repositoryClass external
rm -f "$tmp/chained-marker"
if ! (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL default-branch commit was blocked in an externally governed repository' >&2
  exit 1
fi
[ "$(cat "$tmp/chained-marker")" = chained ] || {
  printf '%s\n' 'FAIL project pre-commit hook did not run for an externally governed repository' >&2
  exit 1
}
git -C "$tmp/work" config serverPolicy.repositoryClass project
if (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL invalid repository class was silently exempted' >&2
  exit 1
fi

# A local repository has no delivery consumers, so the delivery guards are
# skipped — commits on the default branch and in the canonical checkout are
# allowed — while the project hook still runs. Configuring a remote revokes
# the class: the check fails closed rather than silently exempting it.
git -C "$tmp/work" config serverPolicy.repositoryClass local
rm -f "$tmp/chained-marker"
if ! (cd "$tmp/wt" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL task-branch commit was blocked in a local repository' >&2
  exit 1
fi
if ! (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL default-branch commit was blocked in a local repository' >&2
  exit 1
fi
[ "$(cat "$tmp/chained-marker")" = chained ] || {
  printf '%s\n' 'FAIL project pre-commit hook did not run for a local repository' >&2
  exit 1
}
git -C "$tmp/work" remote add origin "$tmp/nowhere.git"
if (cd "$tmp/work" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL local repository with a remote was silently exempted' >&2
  exit 1
fi
git -C "$tmp/work" remote remove origin
git -C "$tmp/work" config --unset serverPolicy.repositoryClass

# A repository the host was never asked to deliver carries no serverPolicy.*
# configuration and sits outside the workspace root. The global hook still runs
# there, but the delivery guards must not: a `git init` + commit that has not
# fetched its remote is ordinary git use, not a policy violation. Measured
# 2026-11-17: before this, every such commit failed with "cannot determine the
# default branch", which broke test fixtures under /tmp.
unmanaged="$tmp/unmanaged"
git init --initial-branch=main "$unmanaged" >/dev/null
git -C "$unmanaged" config user.name test
git -C "$unmanaged" config user.email test@example.com
git init --bare --initial-branch=main "$tmp/unmanaged-origin.git" >/dev/null
git -C "$unmanaged" remote add origin "$tmp/unmanaged-origin.git"
printf 'body\n' >"$unmanaged/file.txt"
git -C "$unmanaged" add -- file.txt
if ! (cd "$unmanaged" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL unenrolled repository could not make its first commit' >&2
  exit 1
fi

# Enrollment is what turns the guard on, and it survives outside the workspace
# root: the same repository becomes governed as soon as the tooling records it.
git -C "$unmanaged" config serverPolicy.defaultBranch main
if (cd "$unmanaged" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL enrolled repository was exempted by its location' >&2
  exit 1
fi
git -C "$unmanaged" config --unset serverPolicy.defaultBranch

# The workspace arm of the same test: a checkout under $HOME/Projects is
# governed even before the audit has written any serverPolicy.* key.
mkdir -p "$HOME/Projects"
git init --initial-branch=main "$HOME/Projects/fresh" >/dev/null
git -C "$HOME/Projects/fresh" config user.name test
git -C "$HOME/Projects/fresh" config user.email test@example.com
if (cd "$HOME/Projects/fresh" && "$hook") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL unclassified checkout inside the workspace root was exempted' >&2
  exit 1
fi

printf '%s\n' 'pre-commit policy tests passed'
