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
cp "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" "$policy_dir/DEVELOPMENT-PORT-REGISTRY.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/AGENTS.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/CLAUDE.md"
cp "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$projects/SERVER-DEVELOPMENT-CONSENSUS.md"
cp "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" "$projects/DEVELOPMENT-PORT-REGISTRY.md"
python3 "$HOME/.local/bin/update-codex-config" "$HOME/.codex/config.toml" \
  "$policy_dir/CODEX-DEVELOPER-INSTRUCTIONS.md"
cp "$base_dir/git-hooks/hook-forwarder" "$hooks/hook-forwarder"
cp "$base_dir/git-hooks/pre-commit" "$hooks/pre-commit"
cp "$base_dir/git-hooks/pre-merge-commit" "$hooks/pre-merge-commit"
cp "$base_dir/git-hooks/pre-push" "$hooks/pre-push"
cp "$base_dir/git-hooks/commit-msg" "$hooks/commit-msg"
chmod +x "$hooks/hook-forwarder" "$hooks/pre-commit" "$hooks/pre-merge-commit" "$hooks/pre-push" "$hooks/commit-msg"

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
    pre-commit|pre-merge-commit|pre-push|commit-msg) ;;
    *) ln -s hook-forwarder "$hooks/$hook" ;;
  esac
done < <(git_hook_names)
(
  cd "$hooks"
  sha256sum hook-forwarder pre-commit pre-merge-commit pre-push commit-msg
) >"$policy_dir/managed-hooks.sha256"
git config --global core.hooksPath "$hooks"
git config --global init.defaultBranch main

git init --initial-branch=main "$projects/repo" >/dev/null
git -C "$projects/repo" config user.name test
git -C "$projects/repo" config user.email test@example.com
git -C "$projects/repo" -c core.hooksPath=/dev/null commit --allow-empty -m initial >/dev/null
mkdir -p "$projects/artifacts/.agent-private/codex-home/.tmp/plugins-clone/.git"
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
git -C "$projects/repo" commit --allow-empty -m 'chore: test chained hook' >/dev/null
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

printf '%s\n' drift >"$projects/DEVELOPMENT-PORT-REGISTRY.md"
if "$audit" "$projects" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL drifted development port registry passed policy audit' >&2
  exit 1
fi
cp "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" "$projects/DEVELOPMENT-PORT-REGISTRY.md"

git init --initial-branch=main "$tmp/external" >/dev/null
git -C "$tmp/external" config user.name test
git -C "$tmp/external" config user.email test@example.com
git -C "$tmp/external" -c core.hooksPath=/dev/null commit --allow-empty -m external >/dev/null
git -C "$tmp/external" worktree add -b feat/external "$projects/external-linked" >/dev/null
config_inventory=$tmp/config-inventory
find_project_git_configs "$projects" >"$config_inventory"
tr '\0' '\n' <"$config_inventory" | grep -q "$tmp/external/.git/config"

# Workspace Layout: visible top-level linked worktrees are reported without
# failing the audit run (hard enforcement lives in dev-worktree start).
"$audit" "$projects" >"$tmp/top-worktree.out" 2>&1 || true
grep -q 'WARN top-level task worktree violates Workspace Layout' \
  "$tmp/top-worktree.out"

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

# Stale task branches -----------------------------------------------------------
# dev-worktree audit only walks registered worktrees, so a branch created in the
# canonical checkout outlives its merge: squash merges hide it from
# `git branch --merged`, and retire() never deletes a remote branch.
stale_repo=$projects/stale-repo
git init --bare --initial-branch=main "$tmp/stale-origin.git" >/dev/null
git init --initial-branch=main "$stale_repo" >/dev/null
git -C "$stale_repo" config user.name test
git -C "$stale_repo" config user.email test@example.com
git -C "$stale_repo" remote add origin "$tmp/stale-origin.git"
git -C "$stale_repo" -c core.hooksPath=/dev/null \
  commit --allow-empty -m base >/dev/null
git -C "$stale_repo" -c core.hooksPath=/dev/null push -u origin main >/dev/null 2>&1
git -C "$stale_repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$stale_repo" config serverPolicy.defaultBranch main

# Integrated: the same patch already landed on main under a different commit,
# which is what squash merge produces.
git -C "$stale_repo" checkout -b feat/integrated >/dev/null 2>&1
printf '%s\n' work >"$stale_repo/feature.txt"
git -C "$stale_repo" add feature.txt
git -C "$stale_repo" -c core.hooksPath=/dev/null \
  commit -m 'feat: integrated work' >/dev/null
git -C "$stale_repo" -c core.hooksPath=/dev/null push -u origin feat/integrated \
  >/dev/null 2>&1
git -C "$stale_repo" checkout main >/dev/null 2>&1
printf '%s\n' work >"$stale_repo/feature.txt"
git -C "$stale_repo" add feature.txt
git -C "$stale_repo" -c core.hooksPath=/dev/null \
  commit -m 'feat: integrated work (squashed)' >/dev/null
git -C "$stale_repo" -c core.hooksPath=/dev/null push origin main >/dev/null 2>&1

# Upstream gone: pushed, then deleted on the remote.
git -C "$stale_repo" checkout -b feat/gone >/dev/null 2>&1
git -C "$stale_repo" -c core.hooksPath=/dev/null \
  commit --allow-empty -m 'feat: gone work' >/dev/null
git -C "$stale_repo" -c core.hooksPath=/dev/null push -u origin feat/gone \
  >/dev/null 2>&1
git -C "$stale_repo" checkout main >/dev/null 2>&1
git -C "$stale_repo" -c core.hooksPath=/dev/null push origin --delete feat/gone \
  >/dev/null 2>&1
git -C "$stale_repo" fetch --prune >/dev/null 2>&1

# Leftover branches are reported without failing the run: deleting unmerged
# work automatically is the outcome this audit exists to prevent.
"$audit" "$projects" >"$tmp/stale-branches.out" 2>&1 || true
grep -q "WARN repo=$stale_repo branch=feat/integrated state=integrated_not_retired" \
  "$tmp/stale-branches.out"
grep -q "WARN repo=$stale_repo branch=feat/gone state=upstream_gone" \
  "$tmp/stale-branches.out"
grep -q 'stale_branches=2' "$tmp/stale-branches.out"

# A branch still checked out in a registered worktree belongs to dev-worktree,
# even when its patches are already integrated.  Point it at the integrated
# commit so it is patch-equivalent to origin/main: this scan must still skip it,
# otherwise every active task worktree would be reported as stale.
git -C "$stale_repo" worktree add -b feat/wip "$tmp/stale-wt" feat/integrated \
  >/dev/null
"$audit" "$projects" >"$tmp/stale-worktree.out" 2>&1 || true
grep -q 'stale_branches=2' "$tmp/stale-worktree.out"
if grep -q "state=.*repo=$stale_repo branch=feat/wip\|branch=feat/wip state=" \
  "$tmp/stale-worktree.out"; then
  printf '%s\n' 'FAIL branch checked out in a worktree was reported stale' >&2
  exit 1
fi
git -C "$stale_repo" worktree remove --force "$tmp/stale-wt" >/dev/null 2>&1
rm -rf "$stale_repo"

# Repository class ---------------------------------------------------------------
# An externally governed repository keeps its own delivery process: the audit
# neither fails it nor rewrites its hook configuration or delivery metadata,
# while an unreadable class is a finding.
external_repo=$projects/company-repo
external_hooks=$tmp/company-project-hooks
mkdir -p "$external_hooks"
git init --initial-branch=main "$external_repo" >/dev/null
git -C "$external_repo" config user.name test
git -C "$external_repo" config user.email test@example.com
git -C "$external_repo" -c core.hooksPath=/dev/null \
  commit --allow-empty -m external >/dev/null
git -C "$external_repo" worktree add --detach "$tmp/company-detached" >/dev/null
git -C "$external_repo" config serverPolicy.repositoryClass external
git -C "$external_repo" config serverPolicy.defaultBranch company-default
git -C "$external_repo" config core.hooksPath "$external_hooks"
"$audit" "$projects" >"$tmp/external-class.out" 2>&1 || true
grep -q "repo $external_repo branch=main default=company-default .* class=external" \
  "$tmp/external-class.out"
if grep -q "FAIL $external_repo " "$tmp/external-class.out"; then
  cat "$tmp/external-class.out" >&2
  printf '%s\n' 'FAIL externally governed repository failed the policy audit' >&2
  exit 1
fi
"$audit" --repair "$projects" >"$tmp/external-class-repair.out" 2>&1 || true
if grep -q "FAIL $external_repo " "$tmp/external-class-repair.out"; then
  cat "$tmp/external-class-repair.out" >&2
  printf '%s\n' 'FAIL externally governed repository failed the repair audit' >&2
  exit 1
fi
[ "$(git -C "$external_repo" config --get core.hooksPath)" = "$external_hooks" ]
[ "$(git -C "$external_repo" config --get serverPolicy.defaultBranch)" = company-default ]
git -C "$external_repo" config serverPolicy.repositoryClass company-managed
if "$audit" "$projects" >"$tmp/external-class-invalid.out" 2>&1; then
  printf '%s\n' 'FAIL invalid repository class was accepted' >&2
  exit 1
fi
grep -q "FAIL $external_repo repository class is invalid: company-managed" \
  "$tmp/external-class-invalid.out"
rm -rf "$external_repo"

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
