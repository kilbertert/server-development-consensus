#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
installer=$base_dir/install.sh
[ "$(id -u)" -ne 0 ] || {
  printf '%s\n' 'SKIP installer integration test requires a non-root user'
  exit 0
}
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export XDG_CONFIG_HOME=$HOME/.config
export SERVER_POLICY_INSTALL_TESTING=1
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/Projects" "$HOME/.codex" "$HOME/custom-hooks" "$tmp/bin"
PATH=$tmp/bin:$PATH
export PATH
export SYSTEMCTL_STATE_DIR=$tmp/systemctl-state
mkdir -p "$SYSTEMCTL_STATE_DIR"
printf '%s\n' 0 >"$SYSTEMCTL_STATE_DIR/available"
printf '%s\n' disabled >"$SYSTEMCTL_STATE_DIR/enabled"
printf '%s\n' inactive >"$SYSTEMCTL_STATE_DIR/active"
printf '%s\n' \
  '#!/bin/sh' \
  'state=$SYSTEMCTL_STATE_DIR' \
  'case "$2" in' \
  '  show-environment) [ "$(cat "$state/available")" = 1 ] ;;' \
  '  is-enabled) cat "$state/enabled"; [ "$(cat "$state/enabled")" = enabled ] ;;' \
  '  is-active) cat "$state/active"; [ "$(cat "$state/active")" = active ] ;;' \
  '  daemon-reload) exit 0 ;;' \
  '  enable) printf "%s\n" enabled >"$state/enabled"; case " $* " in *" --now "*) printf "%s\n" active >"$state/active" ;; esac ;;' \
  '  disable) printf "%s\n" disabled >"$state/enabled" ;;' \
  '  mask) printf "%s\n" masked >"$state/enabled" ;;' \
  '  start) printf "%s\n" active >"$state/active" ;;' \
  '  stop) printf "%s\n" inactive >"$state/active" ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$tmp/bin/systemctl"
chmod +x "$tmp/bin/systemctl"

git init --initial-branch=main "$HOME/Projects/repo" >/dev/null
git -C "$HOME/Projects/repo" config user.name test
git -C "$HOME/Projects/repo" config user.email test@example.com
git -C "$HOME/Projects/repo" commit --allow-empty -m initial >/dev/null
printf '#!/bin/sh\nexit 0\n' >"$HOME/custom-hooks/commit-msg"
chmod +x "$HOME/custom-hooks/commit-msg"
git config --global core.hooksPath "$HOME/custom-hooks"
printf '%s\n' 'model = "gpt-test"' >"$HOME/.codex/config.toml"
printf '%s\n' root-maintained >"$HOME/.codex/AGENTS.md"
chmod 400 "$HOME/.codex/AGENTS.md"

first_output=$("$installer" 2>&1)
printf '%s\n' "$first_output" | grep -q 'server development consensus installed'
[ "$(git config --global --path --get core.hooksPath)" = "$HOME/.config/git/hooks" ]
[ "$(git config --global --path --get serverPolicy.globalChainedHooksPath)" = "$HOME/custom-hooks" ]
grep -q '^## Internal Knowledge And Public Projection Boundary$' "$HOME/Projects/AGENTS.md"
grep -q '^## Standards-Based Engineering$' "$HOME/Projects/AGENTS.md"
[ "$(cat "$HOME/.codex/AGENTS.md")" = root-maintained ]
python3 "$HOME/.local/bin/update-codex-config" --verify "$HOME/.codex/config.toml" \
  "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md"
python3 - "$HOME/.codex/config.toml" <<'PY'
import sys
import tomlkit

config = tomlkit.parse(open(sys.argv[1], encoding="utf-8").read())
assert config["model_context_window"] == 872000
assert config["model_auto_compact_token_limit"] == 700000
assert config["model"] == "gpt-test"
PY
cmp "$base_dir/bin/sync-privileged-policy" "$HOME/.local/bin/sync-privileged-policy"
cmp "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" \
  "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md"
cmp "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" \
  "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md"
[ "$(head -n 1 "$HOME/.local/bin/sync-privileged-policy")" = '#!/usr/bin/python3' ]
cmp "$base_dir/git-hooks/pre-merge-commit" \
  "$HOME/.config/git/hooks/pre-merge-commit"
cmp "$base_dir/git-hooks/commit-msg" \
  "$HOME/.config/git/hooks/commit-msg"
[ "$(wc -l <"$HOME/.config/server-development-consensus/managed-hooks.sha256")" = 5 ]

# GitHub Actions temporarily changes HOME while actions/checkout runs. The
# installed hook must still load the policy library from its managed path.
git init --bare --initial-branch=main "$tmp/actions-remote.git" >/dev/null
git init --initial-branch=main "$tmp/actions-work" >/dev/null
git -C "$tmp/actions-work" config user.name test
git -C "$tmp/actions-work" config user.email test@example.com
git -C "$tmp/actions-work" -c core.hooksPath=/dev/null commit --allow-empty -m initial >/dev/null
git -C "$tmp/actions-work" remote add origin "$tmp/actions-remote.git"
git -C "$tmp/actions-work" -c core.hooksPath=/dev/null push origin HEAD:main >/dev/null
mkdir -p "$tmp/actions-home"
actions_home=$tmp/actions-home
installed_hooks=$HOME/.config/git/hooks
HOME="$actions_home" git -C "$tmp/actions-work" \
  -c core.hooksPath="$installed_hooks" fetch origin

second_output=$("$installer" 2>&1)
printf '%s\n' "$second_output" | grep -q 'audit complete: failures=0 repaired=0'
[ "$(git config --global --path --get serverPolicy.globalChainedHooksPath)" = "$HOME/custom-hooks" ]

export CUSTOM_HOOK_MARKER=$tmp/custom-hook-marker
printf '%s\n' \
  '#!/bin/sh' \
  '. "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"' \
  'printf pre-commit >"$CUSTOM_HOOK_MARKER"' \
  >"$HOME/.config/git/hooks/pre-commit"
chmod +x "$HOME/.config/git/hooks/pre-commit"
"$installer" >/dev/null
custom_chain=$(git config --global --path --get serverPolicy.globalChainedHooksPath)
[ -x "$HOME/.local/bin/dev-worktree" ]
cmp "$base_dir/bin/dev-worktree" "$HOME/.local/bin/dev-worktree"
[ "$custom_chain" != "$HOME/.config/git/hooks" ]
grep -q 'CUSTOM_HOOK_MARKER' "$custom_chain/pre-commit"
[ ! -e "$custom_chain/pre-push" ]
cmp "$HOME/custom-hooks/commit-msg" "$custom_chain/commit-msg"

printf '%s\n' \
  '#!/bin/sh' \
  '. "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"' \
  'cat >/dev/null' \
  'printf pre-push >"$CUSTOM_HOOK_MARKER"' \
  >"$HOME/.config/git/hooks/pre-push"
chmod +x "$HOME/.config/git/hooks/pre-push"
"$installer" >/dev/null
combined_chain=$(git config --global --path --get serverPolicy.globalChainedHooksPath)
[ "$combined_chain" != "$custom_chain" ]
grep -q 'CUSTOM_HOOK_MARKER' "$combined_chain/pre-commit"
grep -q 'CUSTOM_HOOK_MARKER' "$combined_chain/pre-push"
cmp "$HOME/custom-hooks/commit-msg" "$combined_chain/commit-msg"
custom_chain=$combined_chain
cmp "$base_dir/git-hooks/pre-commit" "$HOME/.config/git/hooks/pre-commit"
cmp "$base_dir/git-hooks/pre-push" "$HOME/.config/git/hooks/pre-push"
git -C "$HOME/Projects/repo" switch -c feat/custom-hook-migration >/dev/null
(cd "$HOME/Projects/repo" && "$HOME/.config/git/hooks/pre-commit")
[ "$(cat "$CUSTOM_HOOK_MARKER")" = pre-commit ]
"$installer" >/dev/null
[ "$(git config --global --path --get serverPolicy.globalChainedHooksPath)" = "$custom_chain" ]

git config --global --unset-all serverPolicy.globalChainedHooksPath
printf '%s\n' '# previous managed version' >>"$HOME/.config/git/hooks/pre-push"
(
  cd "$HOME/.config/git/hooks"
  sha256sum hook-forwarder pre-commit pre-merge-commit pre-push commit-msg
) >"$HOME/.config/server-development-consensus/managed-hooks.sha256"
"$installer" >/dev/null
if git config --global --get serverPolicy.globalChainedHooksPath >/dev/null 2>&1; then
  printf '%s\n' 'FAIL manifest-verified managed hooks were preserved as a chain' >&2
  exit 1
fi

printf '%s\n' before-rollback >"$HOME/Projects/AGENTS.md"
printf '%s\n' registry-before-rollback >"$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md"
printf '%s\n' canonical-registry-before-rollback \
  >"$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md"
printf '%s\n' '# sentinel' >>"$HOME/.local/bin/dev-start"
cp "$HOME/.local/bin/dev-start" "$tmp/dev-start.before"
preserved_agent_identity=$(stat -c '%d:%i:%u:%g:%a' "$HOME/.codex/AGENTS.md")
export SERVER_POLICY_INSTALL_FAIL_STAGE=after-files
if "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL injected installer failure returned success' >&2
  exit 1
fi
unset SERVER_POLICY_INSTALL_FAIL_STAGE
[ "$(cat "$HOME/Projects/AGENTS.md")" = before-rollback ]
[ "$(cat "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md")" = registry-before-rollback ]
[ "$(cat "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md")" = \
  canonical-registry-before-rollback ]
cmp "$tmp/dev-start.before" "$HOME/.local/bin/dev-start"
[ "$(stat -c '%d:%i:%u:%g:%a' "$HOME/.codex/AGENTS.md")" = \
  "$preserved_agent_identity" ]
[ "$(cat "$HOME/.codex/AGENTS.md")" = root-maintained ]
[ "$(git config --global --path --get core.hooksPath)" = "$HOME/.config/git/hooks" ]

git config --global core.hooksPath "$HOME/custom-hooks"
git config --global pull.ff false
git config --global commit.verbose false
before_gitconfig=$(sha256sum "$HOME/.gitconfig" | awk '{print $1}')
export SERVER_POLICY_INSTALL_FAIL_STAGE=after-git-config
if "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL post-Git-config installer failure returned success' >&2
  exit 1
fi
unset SERVER_POLICY_INSTALL_FAIL_STAGE
[ "$(sha256sum "$HOME/.gitconfig" | awk '{print $1}')" = "$before_gitconfig" ]
[ "$(git config --global --path --get core.hooksPath)" = "$HOME/custom-hooks" ]
[ "$(git config --global --get pull.ff)" = false ]
[ "$(git config --global --get commit.verbose)" = false ]

printf '%s\n' 1 >"$SYSTEMCTL_STATE_DIR/available"
printf '%s\n' disabled >"$SYSTEMCTL_STATE_DIR/enabled"
printf '%s\n' inactive >"$SYSTEMCTL_STATE_DIR/active"
export SERVER_POLICY_INSTALL_FAIL_STAGE=after-systemd
if "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL post-systemd installer failure returned success' >&2
  exit 1
fi
unset SERVER_POLICY_INSTALL_FAIL_STAGE
[ "$(cat "$SYSTEMCTL_STATE_DIR/enabled")" = disabled ]
[ "$(cat "$SYSTEMCTL_STATE_DIR/active")" = inactive ]
printf '%s\n' 0 >"$SYSTEMCTL_STATE_DIR/available"

(
  exec 9>"$HOME/.local/state/server-development-consensus/config.lock"
  flock -x 9
  printf '%s\n' locked >"$tmp/install-lock-ready"
  while [ ! -e "$tmp/release-install-lock" ]; do :; done
) &
lock_pid=$!
while [ ! -e "$tmp/install-lock-ready" ]; do :; done
if "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL concurrent installer lock was ignored' >&2
  exit 1
fi
: >"$tmp/release-install-lock"
wait "$lock_pid"

fresh_home=$tmp/fresh-home
mkdir -p "$fresh_home/.codex"
printf '%s\n' 'invalid = [' >"$fresh_home/.codex/config.toml"
if HOME=$fresh_home SERVER_POLICY_INSTALL_TESTING=1 GIT_CONFIG_NOSYSTEM=1 \
  "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL malformed preflight config was accepted' >&2
  exit 1
fi
[ ! -e "$fresh_home/Projects" ]

symlink_home=$tmp/symlink-home
mkdir -p "$symlink_home/.codex"
printf '%s\n' 'model = "gpt-test"' >"$symlink_home/.codex/config.toml"
printf '%s\n' gitconfig-sentinel >"$tmp/gitconfig-target"
ln -s "$tmp/gitconfig-target" "$symlink_home/.gitconfig"
if HOME=$symlink_home SERVER_POLICY_INSTALL_TESTING=1 GIT_CONFIG_NOSYSTEM=1 \
  "$installer" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL symlinked .gitconfig was accepted' >&2
  exit 1
fi
[ "$(cat "$tmp/gitconfig-target")" = gitconfig-sentinel ]
[ ! -e "$symlink_home/Projects" ]

printf '%s\n' 'installer integration tests passed'
