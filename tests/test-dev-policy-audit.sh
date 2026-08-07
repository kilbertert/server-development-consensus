#!/usr/bin/env bash
set -Eeuo pipefail

# Keep failures actionable in CI.  This script intentionally exercises many
# rejected states under `if`/`set +e`, so the ERR trap only reports an
# unexpected command that actually aborts the test process.
trap 'status=$?; printf "FAIL test-dev-policy-audit.sh:%s command=%q status=%s\\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
audit=$base_dir/bin/dev-policy-audit
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export SERVER_POLICY_HOME=$HOME
export XDG_CONFIG_HOME=$HOME/.config
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
projects=$HOME/Projects
hooks=$HOME/.config/git/hooks
policy_dir=$HOME/.config/server-development-consensus
mkdir -p "$HOME/.local/lib/server-development-consensus" "$HOME/.local/bin" \
  "$HOME/.codex" "$projects" "$hooks" "$policy_dir"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
cp "$base_dir/bin/dev-worktree" "$HOME/.local/bin/dev-worktree"
chmod +x "$HOME/.local/bin/dev-worktree"
cp "$base_dir/bin/update-codex-config" "$HOME/.local/bin/update-codex-config"
chmod +x "$HOME/.local/bin/update-codex-config"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$policy_dir/SERVER-DEVELOPMENT-CONSENSUS.md"
cp "$base_dir/CODEX-DEVELOPER-INSTRUCTIONS.md" "$policy_dir/CODEX-DEVELOPER-INSTRUCTIONS.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/AGENTS.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/CLAUDE.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/SERVER-DEVELOPMENT-CONSENSUS.md"
python3 "$HOME/.local/bin/update-codex-config" "$HOME/.codex/config.toml" \
  "$policy_dir/CODEX-DEVELOPER-INSTRUCTIONS.md"
cp "$base_dir/git-hooks/hook-forwarder" "$hooks/hook-forwarder"
cp "$base_dir/git-hooks/pre-commit" "$hooks/pre-commit"
cp "$base_dir/git-hooks/pre-merge-commit" "$hooks/pre-merge-commit"
cp "$base_dir/git-hooks/pre-push" "$hooks/pre-push"
chmod +x "$hooks/hook-forwarder" "$hooks/pre-commit" "$hooks/pre-merge-commit" "$hooks/pre-push"

# shellcheck disable=SC1090
source "$base_dir/lib/dev-git-common.sh"
if (cd "$tmp" && chained_hook_for reference-transaction >/dev/null 2>&1); then
  no_repo_chain_status=0
else
  no_repo_chain_status=$?
fi
[ "$no_repo_chain_status" -eq 1 ] || {
  printf 'FAIL no-repository hook lookup returned %s instead of no chain\n' \
    "$no_repo_chain_status" >&2
  exit 1
}
while IFS= read -r hook; do
  case $hook in
    pre-commit|pre-merge-commit|pre-push) ;;
    *) ln -s hook-forwarder "$hooks/$hook" ;;
  esac
done < <(git_hook_names)
(
  cd "$hooks"
  sha256sum hook-forwarder pre-commit pre-merge-commit pre-push
) >"$policy_dir/managed-hooks.sha256"
git config --global core.hooksPath "$hooks"
git config --global init.defaultBranch main

git init --initial-branch=main "$projects/repo" >/dev/null
git -C "$projects/repo" config user.name test
git -C "$projects/repo" config user.email test@example.com
git -C "$projects/repo" -c core.hooksPath=/dev/null commit --allow-empty -m initial >/dev/null
mkdir -p "$projects/repo/.project-hooks"
printf '#!/bin/sh\nprintf executed >"%s"\n' "$tmp/commit-msg-ran" \
  >"$projects/repo/.project-hooks/commit-msg"
chmod +x "$projects/repo/.project-hooks/commit-msg"
git -C "$projects/repo" config core.hooksPath "$projects/repo/.project-hooks"

if repair_output=$("$audit" --repair "$projects"); then
  :
else
  audit_status=$?
  printf 'FAIL initial policy audit returned %s:\n%s\n' \
    "$audit_status" "$repair_output" >&2
  exit "$audit_status"
fi
[ "$(git -C "$projects/repo" config --local --get core.hooksPath)" = "$hooks" ]
[ "$(git -C "$projects/repo" config --local --get serverPolicy.chainedHooksPath)" = "$projects/repo/.project-hooks" ]

git init --initial-branch=main "$projects/hardlink-chain" >/dev/null
git -C "$projects/hardlink-chain" config user.name test
git -C "$projects/hardlink-chain" config user.email test@example.com
git -C "$projects/hardlink-chain" -c core.hooksPath=/dev/null \
  commit --allow-empty -m initial >/dev/null
mkdir "$projects/hardlink-chain/.hardlink-hooks"
ln "$hooks/pre-commit" "$projects/hardlink-chain/.hardlink-hooks/pre-commit"
git -C "$projects/hardlink-chain" config core.hooksPath .hardlink-hooks
if "$audit" --repair "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL audit migrated a hard-linked managed hook as a chain' >&2
  exit 1
fi
[ "$(git -C "$projects/hardlink-chain" config --local --get core.hooksPath)" = \
  .hardlink-hooks ]
rm -rf "$projects/hardlink-chain"

printf '%s\n' sentinel >"$tmp/redirected-global-config"
if GIT_CONFIG_GLOBAL=$tmp/redirected-global-config \
  "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL audit accepted redirected global Git configuration' >&2
  exit 1
fi
[ "$(cat "$tmp/redirected-global-config")" = sentinel ]
if HOME=$tmp/other-home "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL audit accepted a HOME outside the policy account' >&2
  exit 1
fi
printf '%s\n' "$repair_output" | grep -q 'failures=0'
git -C "$projects/repo" switch -c feat/audit >/dev/null
git -C "$projects/repo" commit --allow-empty -m chained >/dev/null
[ "$(cat "$tmp/commit-msg-ran")" = executed ]

second_repair_output=$("$audit" --repair "$projects")
printf '%s\n' "$second_repair_output" | grep -q 'audit complete: failures=0 repaired=0'
[ "$(git -C "$projects/repo" config --local --get core.hooksPath)" = "$hooks" ]
[ "$(git -C "$projects/repo" config --local --get serverPolicy.chainedHooksPath)" = "$projects/repo/.project-hooks" ]

mkdir "$tmp/orphan-global-hooks"
printf '#!/bin/sh\nexit 0\n' >"$tmp/orphan-global-hooks/pre-commit"
chmod +x "$tmp/orphan-global-hooks/pre-commit"
git config --global --unset-all core.hooksPath
git config --global serverPolicy.globalChainedHooksPath "$tmp/orphan-global-hooks"
stale_chain_repair_output=$("$audit" --repair "$projects")
printf '%s\n' "$stale_chain_repair_output" | grep -q 'audit complete: failures=0'
[ "$(git config --global --path --get core.hooksPath)" = "$hooks" ]
if git config --global --get serverPolicy.globalChainedHooksPath >/dev/null 2>&1; then
  printf '%s\n' 'FAIL stale global hook chain survived repair without a source hooksPath' >&2
  exit 1
fi

cp "$hooks/pre-commit" "$tmp/pre-commit.before-tamper"
printf '#!/bin/sh\nexit 0\n' >"$hooks/pre-commit"
chmod +x "$hooks/pre-commit"
if "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL tampered managed pre-commit hook passed audit' >&2
  exit 1
fi
cp "$tmp/pre-commit.before-tamper" "$hooks/pre-commit"
chmod +x "$hooks/pre-commit"

git -C "$projects/repo" worktree add -b feat/linked "$projects/linked" main >/dev/null
audit_output=$("$audit" "$projects")
printf '%s\n' "$audit_output" | grep -q "repo $projects/repo "
printf '%s\n' "$audit_output" | grep -q "repo $projects/linked "
printf '%s\n' pending >"$projects/linked/pending.txt"
git -C "$projects/repo" -c core.hooksPath=/dev/null \
  worktree add "$projects/default-main" main >/dev/null
printf '%s\n' advanced >"$projects/default-main/main-advance.txt"
git -C "$projects/default-main" add main-advance.txt
git -C "$projects/default-main" -c core.hooksPath=/dev/null commit -m advance-main >/dev/null
git -C "$projects/repo" -c core.hooksPath=/dev/null \
  worktree remove "$projects/default-main"
if "$audit" "$projects" >"$tmp/worktree-lifecycle.out" 2>&1; then
  printf '%s\n' 'FAIL uncommitted-only-behind worktree passed policy audit' >&2
  exit 1
fi
grep -q 'state=uncommitted_only_behind' "$tmp/worktree-lifecycle.out"
rm "$projects/linked/pending.txt"
git -C "$projects/linked" -c core.hooksPath=/dev/null \
  merge --ff-only main >/dev/null

git config --global serverPolicy.globalChainedHooksPath "$hooks"
if "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL self-referential global hook chain passed audit' >&2
  exit 1
fi
git config --global --unset-all serverPolicy.globalChainedHooksPath

mkdir "$tmp/loop-chain"
ln -s "$hooks/commit-msg" "$tmp/loop-chain/commit-msg"
git config --global serverPolicy.globalChainedHooksPath "$tmp/loop-chain"
if "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL per-hook self-reference passed audit' >&2
  exit 1
fi
git config --global --unset-all serverPolicy.globalChainedHooksPath

printf '%s\n' drift >"$projects/AGENTS.md"
if "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL drifted global policy copy passed audit' >&2
  exit 1
fi
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/AGENTS.md"

git init --initial-branch=main "$tmp/external" >/dev/null
git -C "$tmp/external" config user.name test
git -C "$tmp/external" config user.email test@example.com
git -C "$tmp/external" -c core.hooksPath=/dev/null commit --allow-empty -m external >/dev/null
git -C "$tmp/external" worktree add -b feat/external "$projects/external-linked" >/dev/null
config_inventory=$tmp/config-inventory
find_project_git_configs "$projects" >"$config_inventory"
tr '\0' '\n' <"$config_inventory" | grep -q "$tmp/external/.git/config"

git init --bare --initial-branch=main "$tmp/unresolved-origin.git" >/dev/null
git init --initial-branch=main "$projects/stale-default" >/dev/null
git -C "$projects/stale-default" config user.name test
git -C "$projects/stale-default" config user.email test@example.com
git -C "$projects/stale-default" -c core.hooksPath=/dev/null \
  commit --allow-empty -m stale >/dev/null
git -C "$projects/stale-default" remote add origin "$tmp/unresolved-origin.git"
git -C "$projects/stale-default" config serverPolicy.defaultBranch main
if "$audit" --repair "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL unresolved origin default branch passed repair audit' >&2
  exit 1
fi
if git -C "$projects/stale-default" config --get serverPolicy.defaultBranch \
  >/dev/null 2>&1; then
  printf '%s\n' 'FAIL stale default-branch cache survived failed resolution' >&2
  exit 1
fi
rm -rf "$projects/stale-default"

git init --initial-branch=main "$projects/broken" >/dev/null
printf '%s\n' '[broken' >"$projects/broken/.git/config"
if "$audit" "$projects" >"$tmp/broken.out" 2>&1; then
  printf '%s\n' 'FAIL repository inspection errors were ignored' >&2
  exit 1
fi
grep -q "FAIL $projects/broken cannot inspect repository state" "$tmp/broken.out"

if "$audit" "$HOME/missing" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL missing projects root was accepted' >&2
  exit 1
fi

printf '%s\n' 'development policy audit tests passed'
