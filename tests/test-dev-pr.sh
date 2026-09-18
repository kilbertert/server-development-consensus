#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/lib/server-development-consensus" "$HOME/.local/bin" "$tmp/bin"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/bin/dev-pr" "$HOME/.local/bin/dev-pr"
chmod +x "$HOME/.local/bin/dev-pr"
export GH_CALLS=$tmp/gh.calls
: >"$GH_CALLS"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$GH_CALLS"' \
  'case "$1" in' \
  '  repo) case "$3" in *enterprise-fork.git) printf "%s\n" ghe.example/fork-owner/repo ;; *fork.git) printf "%s\n" github.com/fork-owner/repo ;; *unrelated.git) printf "%s\n" github.com/other/repo ;; *) printf "%s\n" github.com/owner/repo ;; esac ;;' \
  '  api) case "$4" in repos/owner/repo) printf "%s\n" owner/repo ;; repos/fork-owner/repo) printf "%s\n" owner/repo ;; repos/other/repo) printf "%s\n" another/base ;; *) exit 2 ;; esac ;;' \
  '  pr) case "$2" in list) if [ -n "${GH_EXISTING_PR:-}" ]; then printf "%s\n" "$GH_EXISTING_PR"; fi ;; view) printf "%s\n" https://example.test/pr/existing ;; create) printf "%s\n" https://example.test/pr/new ;; *) exit 2 ;; esac ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
PATH=$tmp/bin:$PATH
export PATH

git init --bare --initial-branch=main "$tmp/remote.git" >/dev/null
git init --initial-branch=main "$tmp/seed" >/dev/null
git -C "$tmp/seed" config user.name test
git -C "$tmp/seed" config user.email test@example.com
git -C "$tmp/seed" commit --allow-empty -m initial >/dev/null
git -C "$tmp/seed" remote add origin "$tmp/remote.git"
git -C "$tmp/seed" push -u origin main >/dev/null

assert_no_gh_calls() {
  [ ! -s "$GH_CALLS" ] || {
    printf '%s\n' 'FAIL gh was called after a local policy rejection' >&2
    exit 1
  }
}

git clone "$tmp/remote.git" "$tmp/no-change" >/dev/null 2>&1
git -C "$tmp/no-change" config serverPolicy.defaultBranch main
git -C "$tmp/no-change" switch -c feat/no-change >/dev/null
if (cd "$tmp/no-change" && "$HOME/.local/bin/dev-pr") >"$tmp/no-change.out" 2>&1; then
  printf '%s\n' 'FAIL PR creation allowed a branch with no changes' >&2
  exit 1
fi
grep -q 'no changes relative to the default branch' "$tmp/no-change.out"
assert_no_gh_calls

git clone "$tmp/remote.git" "$tmp/option-branch" >/dev/null 2>&1
git -C "$tmp/option-branch" config serverPolicy.defaultBranch main
git -C "$tmp/option-branch" update-ref refs/heads/--mirror HEAD
git -C "$tmp/option-branch" symbolic-ref HEAD refs/heads/--mirror
: >"$GH_CALLS"
if (cd "$tmp/option-branch" && "$HOME/.local/bin/dev-pr") \
  >"$tmp/option-branch.out" 2>&1; then
  printf '%s\n' 'FAIL option-shaped branch name was accepted' >&2
  exit 1
fi
grep -q 'switch to a task branch' "$tmp/option-branch.out"
assert_no_gh_calls

git init --initial-branch=feat/unrelated "$tmp/unrelated" >/dev/null
git -C "$tmp/unrelated" config user.name test
git -C "$tmp/unrelated" config user.email test@example.com
git -C "$tmp/unrelated" config serverPolicy.defaultBranch main
git -C "$tmp/unrelated" commit --allow-empty -m unrelated >/dev/null
git -C "$tmp/unrelated" remote add origin "$tmp/remote.git"
git -C "$tmp/unrelated" fetch origin \
  '+refs/heads/main:refs/remotes/origin/main' >/dev/null
git -C "$tmp/unrelated" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
if (cd "$tmp/unrelated" && "$HOME/.local/bin/dev-pr") >"$tmp/unrelated.out" 2>&1; then
  printf '%s\n' 'FAIL PR creation allowed a branch with no common baseline' >&2
  exit 1
fi
grep -q 'update the task branch' "$tmp/unrelated.out"
assert_no_gh_calls

git init --bare --initial-branch=main "$tmp/empty.git" >/dev/null
git init --initial-branch=feat/missing "$tmp/missing" >/dev/null
git -C "$tmp/missing" config user.name test
git -C "$tmp/missing" config user.email test@example.com
git -C "$tmp/missing" config serverPolicy.defaultBranch main
git -C "$tmp/missing" commit --allow-empty -m missing >/dev/null
git -C "$tmp/missing" remote add origin "$tmp/empty.git"
if (cd "$tmp/missing" && "$HOME/.local/bin/dev-pr") >/dev/null 2>&1; then
  printf '%s\n' 'FAIL PR creation allowed a missing remote default branch' >&2
  exit 1
fi
assert_no_gh_calls

git clone "$tmp/remote.git" "$tmp/valid" >/dev/null 2>&1
git -C "$tmp/valid" config user.name test
git -C "$tmp/valid" config user.email test@example.com
git -C "$tmp/valid" config serverPolicy.defaultBranch main
git -C "$tmp/valid" switch -c feat/valid >/dev/null
printf '%s\n' change >"$tmp/valid/change.txt"
git -C "$tmp/valid" add change.txt
git -C "$tmp/valid" commit -m change >/dev/null
(cd "$tmp/valid" && "$HOME/.local/bin/dev-pr") >"$tmp/valid.out"
grep -q 'https://example.test/pr/new' "$tmp/valid.out"
git --git-dir="$tmp/remote.git" show-ref --verify --quiet refs/heads/feat/valid
grep -q 'repo view .*remote.git --json nameWithOwner,url --jq' "$GH_CALLS"
grep -q 'pr list --repo github.com/owner/repo --base main --head feat/valid' "$GH_CALLS"
grep -q 'pr create --repo github.com/owner/repo --base main --head feat/valid --fill' "$GH_CALLS"

git init --bare --initial-branch=main "$tmp/second-push.git" >/dev/null
git clone "$tmp/remote.git" "$tmp/multiple-push" >/dev/null 2>&1
git -C "$tmp/multiple-push" config user.name test
git -C "$tmp/multiple-push" config user.email test@example.com
git -C "$tmp/multiple-push" config serverPolicy.defaultBranch main
git -C "$tmp/multiple-push" switch -c feat/multiple-push >/dev/null
printf '%s\n' multiple >"$tmp/multiple-push/change.txt"
git -C "$tmp/multiple-push" add change.txt
git -C "$tmp/multiple-push" commit -m multiple >/dev/null
git -C "$tmp/multiple-push" remote set-url --add --push origin "$tmp/remote.git"
git -C "$tmp/multiple-push" remote set-url --add --push origin "$tmp/second-push.git"
: >"$GH_CALLS"
if (cd "$tmp/multiple-push" && "$HOME/.local/bin/dev-pr") \
  >"$tmp/multiple-push.out" 2>&1; then
  printf '%s\n' 'FAIL dev-pr accepted multiple origin push targets' >&2
  exit 1
fi
grep -q 'exactly one push target' "$tmp/multiple-push.out"
assert_no_gh_calls
! git --git-dir="$tmp/remote.git" show-ref --verify --quiet refs/heads/feat/multiple-push
! git --git-dir="$tmp/second-push.git" show-ref --verify --quiet refs/heads/feat/multiple-push

git clone --bare "$tmp/remote.git" "$tmp/fork.git" >/dev/null 2>&1
git clone "$tmp/remote.git" "$tmp/forked" >/dev/null 2>&1
git -C "$tmp/forked" config user.name test
git -C "$tmp/forked" config user.email test@example.com
git -C "$tmp/forked" config serverPolicy.defaultBranch main
git -C "$tmp/forked" remote set-url --push origin "$tmp/fork.git"
git -C "$tmp/forked" switch -c feat/fork >/dev/null
printf '%s\n' fork-change >"$tmp/forked/fork.txt"
git -C "$tmp/forked" add fork.txt
git -C "$tmp/forked" commit -m fork-change >/dev/null
: >"$GH_CALLS"
(cd "$tmp/forked" && "$HOME/.local/bin/dev-pr") >"$tmp/forked.out"
grep -q 'https://example.test/pr/new' "$tmp/forked.out"
! git --git-dir="$tmp/remote.git" show-ref --verify --quiet refs/heads/feat/fork
git --git-dir="$tmp/fork.git" show-ref --verify --quiet refs/heads/feat/fork
grep -q 'repo view .*remote.git --json nameWithOwner,url --jq' "$GH_CALLS"
grep -q 'repo view .*fork.git --json nameWithOwner,url --jq' "$GH_CALLS"
grep -q 'api --hostname github.com repos/owner/repo --jq' "$GH_CALLS"
grep -q 'api --hostname github.com repos/fork-owner/repo --jq' "$GH_CALLS"
grep -q 'pr list --repo github.com/owner/repo --base main --head fork-owner:feat/fork' "$GH_CALLS"
grep -q 'pr create --repo github.com/owner/repo --base main --head fork-owner:feat/fork --fill' "$GH_CALLS"
if git -C "$tmp/forked" config --get branch.feat/fork.remote >/dev/null 2>&1; then
  printf '%s\n' 'FAIL fork push created an upstream that fetches from the base repository' >&2
  exit 1
fi

git init --bare --initial-branch=main "$tmp/unrelated.git" >/dev/null
git clone "$tmp/remote.git" "$tmp/unrelated-push" >/dev/null 2>&1
git -C "$tmp/unrelated-push" config user.name test
git -C "$tmp/unrelated-push" config user.email test@example.com
git -C "$tmp/unrelated-push" config serverPolicy.defaultBranch main
git -C "$tmp/unrelated-push" remote set-url --push origin "$tmp/unrelated.git"
git -C "$tmp/unrelated-push" switch -c feat/unrelated-push >/dev/null
printf '%s\n' unrelated >"$tmp/unrelated-push/unrelated.txt"
git -C "$tmp/unrelated-push" add unrelated.txt
git -C "$tmp/unrelated-push" commit -m unrelated-push >/dev/null
: >"$GH_CALLS"
if (cd "$tmp/unrelated-push" && "$HOME/.local/bin/dev-pr") \
  >"$tmp/unrelated-push.out" 2>&1; then
  printf '%s\n' 'FAIL dev-pr pushed to an unrelated repository' >&2
  exit 1
fi
! git --git-dir="$tmp/unrelated.git" show-ref --verify --quiet refs/heads/feat/unrelated-push
grep -q 'origin push target is not in the fetch repository fork network' \
  "$tmp/unrelated-push.out"

git clone --bare "$tmp/remote.git" "$tmp/enterprise-fork.git" >/dev/null 2>&1
git clone "$tmp/remote.git" "$tmp/host-mismatch" >/dev/null 2>&1
git -C "$tmp/host-mismatch" config user.name test
git -C "$tmp/host-mismatch" config user.email test@example.com
git -C "$tmp/host-mismatch" config serverPolicy.defaultBranch main
git -C "$tmp/host-mismatch" remote set-url --push origin "$tmp/enterprise-fork.git"
git -C "$tmp/host-mismatch" switch -c feat/host-mismatch >/dev/null
printf '%s\n' host-mismatch >"$tmp/host-mismatch/host.txt"
git -C "$tmp/host-mismatch" add host.txt
git -C "$tmp/host-mismatch" commit -m host-mismatch >/dev/null
: >"$GH_CALLS"
if (cd "$tmp/host-mismatch" && "$HOME/.local/bin/dev-pr") \
  >"$tmp/host-mismatch.out" 2>&1; then
  printf '%s\n' 'FAIL dev-pr accepted fetch and push repositories on different hosts' >&2
  exit 1
fi
grep -q 'must use the same GitHub host' "$tmp/host-mismatch.out" || {
  cat "$tmp/host-mismatch.out" >&2
  exit 1
}
! git --git-dir="$tmp/enterprise-fork.git" show-ref --verify --quiet \
  refs/heads/feat/host-mismatch

: >"$GH_CALLS"
if (cd "$tmp/valid" && "$HOME/.local/bin/dev-pr" --base other) >/dev/null 2>&1; then
  printf '%s\n' 'FAIL dev-pr accepted a target-overriding option' >&2
  exit 1
fi
assert_no_gh_calls

# An externally governed repository delivers through its own process, so this
# GitHub-only command must refuse before it touches the network.
: >"$GH_CALLS"
git -C "$tmp/valid" config serverPolicy.repositoryClass external
if (cd "$tmp/valid" && "$HOME/.local/bin/dev-pr") >"$tmp/external-pr.out" 2>&1; then
  printf '%s\n' 'FAIL dev-pr ran in an externally governed repository' >&2
  exit 1
fi
grep -q 'externally governed' "$tmp/external-pr.out"
assert_no_gh_calls
git -C "$tmp/valid" config --unset serverPolicy.repositoryClass

printf '%s\n' 'dev-pr workflow tests passed'
