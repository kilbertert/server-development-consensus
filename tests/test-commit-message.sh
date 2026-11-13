#!/bin/sh
set -eu
base_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
check=$base_dir/bin/dev-commit-message

for title in 'feat: add login' 'fix(api): handle timeout' 'feat(api)!: change response' \
  'revert: remove login' 'ci: validate PR title'; do
  sh "$check" "$title"
done
for title in '' '# comment' 'fix:no space' 'fix: ' 'feat(): empty scope' \
  'feat(a)b): malformed scope' 'feat: first
second' "$(printf 'fix: carriage\rreturn')" '$(exit 0)' 'update'; do
  if sh "$check" "$title" >/dev/null 2>&1; then
    printf 'FAIL invalid title accepted: %s\n' "$title" >&2
    exit 1
  fi
done
if env GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=serverPolicy.commitMessageOverride \
  GIT_CONFIG_VALUE_0=default-branch-only sh "$check" update >/dev/null 2>&1; then
  printf '%s\n' 'FAIL local override exempted the final title' >&2
  exit 1
fi
if sh "$check" >/dev/null 2>&1 || sh "$check" 'fix: a' extra >/dev/null 2>&1; then
  printf '%s\n' 'FAIL invalid argument count accepted' >&2
  exit 1
fi
printf '%s\n' 'portable commit-message tests passed'
