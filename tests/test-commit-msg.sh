#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
hook=$base_dir/git-hooks/commit-msg
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
git -C "$tmp/work" commit --allow-empty -m initial >/dev/null
git -C "$tmp/work" switch -c feat/test >/dev/null

run_check() {
  msg=$1
  printf '%s\n' "$msg" >"$tmp/msg"
  set +e
  (cd "$tmp/work" && "$hook" "$tmp/msg") >/dev/null 2>&1
  status=$?
  set -e
  return "$status"
}

run_check 'feat: add login' && run_check 'feat(user): add login' && \
run_check 'fix: correct timeout' && run_check 'docs: update readme' && \
run_check 'chore(deps): bump lodash' && run_check 'refactor!: rework api' || {
  printf '%s\n' 'FAIL valid conventional commit was rejected' >&2
  exit 1
}

# Conventional Commits allows an optional `!` breaking marker before the colon,
# after the optional scope. The four shapes must hold for every type — the
# `<type>(<scope>)!:` form was the one the enumerated pattern missed.
for type in feat fix docs style refactor perf test chore build ci revert; do
  for subject in "$type: a" "$type(scope): a" "$type!: a" "$type(scope)!: a"; do
    run_check "$subject" || {
      printf 'FAIL valid commit message "%s" was rejected\n' "$subject" >&2
      exit 1
    }
  done
done

for bad in 'nonsense' 'Feat: add login' 'feat(api) add login' 'feat:' 'feat' 'fix : x' \
  'feat(api)!x' 'feat()!: a' 'feat(): a' '!: a' 'feat(bad' '(x): a'; do
  if run_check "$bad"; then
    printf 'FAIL invalid commit message "%s" was accepted\n' "$bad" >&2
    exit 1
  fi
done

# Comments and empty message files are ignored.
run_check '# this is a comment' || {
  printf '%s\n' 'FAIL commented message was rejected' >&2
  exit 1
}
: >"$tmp/msg"
if ! (cd "$tmp/work" && "$hook" "$tmp/msg") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL empty message file was rejected' >&2
  exit 1
fi
printf '%s\n' 'some message' >"$tmp/msg"
if run_check ''; then
  printf '%s\n' 'FAIL blank first line was accepted' >&2
  exit 1
fi

# An explicit override opts the repository out of the check.
git -C "$tmp/work" config serverPolicy.commitMessageOverride default-branch-only
run_check 'legacy message without type' || {
  printf '%s\n' 'FAIL explicit override did not opt out' >&2
  exit 1
}
git -C "$tmp/work" config --unset serverPolicy.commitMessageOverride

# An externally governed repository keeps its own commit convention, and an
# unreadable or invalid class stops the commit instead of exempting it.
git -C "$tmp/work" config serverPolicy.repositoryClass external
run_check 'legacy message without type' || {
  printf '%s\n' 'FAIL externally governed repository enforced Conventional Commits' >&2
  exit 1
}
git -C "$tmp/work" config serverPolicy.repositoryClass conventional
if run_check 'feat: add login'; then
  printf '%s\n' 'FAIL invalid repository class was silently exempted' >&2
  exit 1
fi
git -C "$tmp/work" config --unset serverPolicy.repositoryClass
if run_check 'legacy message without type'; then
  printf '%s\n' 'FAIL commit contract did not resume after the class was cleared' >&2
  exit 1
fi

printf '%s\n' 'commit-msg policy tests passed'
