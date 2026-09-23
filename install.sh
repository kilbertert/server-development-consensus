#!/bin/sh
set -eu

if [ "${SERVER_POLICY_INSTALL_TESTING:-0}" = 1 ]; then
  expected_home=$HOME
  expected_user=$(id -un)
else
  expected_home=/home/claude
  expected_user=claude
fi
if [ "$(id -un)" != "$expected_user" ] || [ "$HOME" != "$expected_home" ]; then
  printf 'error: this installer must run as %s with HOME=%s\n' \
    "$expected_user" "$expected_home" >&2
  exit 1
fi

base_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
hooks_dir=$HOME/.config/git/hooks
common_source=$base_dir/lib/dev-git-common.sh
policy_dir=$HOME/.config/server-development-consensus
state_dir=$HOME/.local/state/server-development-consensus
lock_file=$state_dir/config.lock
timestamp=$(date +%Y%m%d-%H%M%S)-$$
backup_dir=$state_dir/backups/$timestamp
project_config_list=
rollback_ready=false
install_succeeded=false
created_chain_target=

for command_name in git install tar python3 find sort xargs readlink sha256sum flock stat; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done
python3 -c 'import tomlkit' >/dev/null 2>&1 || {
  printf '%s\n' 'error: Python dependency tomlkit is required by the installer' >&2
  exit 1
}
if [ -L "$HOME/.gitconfig" ]; then
  printf '%s\n' 'error: refusing symlinked ~/.gitconfig; migrate it to a regular file before installation' >&2
  exit 1
fi

umask 077
install -d -m 700 "$state_dir"
exec 9>"$lock_file"
if ! flock -n 9; then
  printf '%s\n' 'error: another server development consensus installation is running' >&2
  exit 1
fi

systemd_user_available=false
timer_enabled_state=not-found
timer_active_state=inactive
if command -v systemctl >/dev/null 2>&1 &&
   systemctl --user show-environment >/dev/null 2>&1; then
  systemd_user_available=true
  timer_enabled_state=$(systemctl --user is-enabled dev-policy-audit.timer 2>/dev/null || true)
  timer_active_state=$(systemctl --user is-active dev-policy-audit.timer 2>/dev/null || true)
fi

backup_file() {
  source_path=$1
  backup_name=$2
  if [ -e "$source_path" ] || [ -L "$source_path" ]; then
    : >"$backup_dir/$backup_name.present"
    cp -a "$source_path" "$backup_dir/$backup_name"
  fi
}

backup_directory_state() {
  directory_path=$1
  backup_name=$2
  if [ -d "$directory_path" ] && [ ! -L "$directory_path" ]; then
    : >"$backup_dir/$backup_name.present"
    stat -c '%a' "$directory_path" >"$backup_dir/$backup_name.mode"
  elif [ -e "$directory_path" ] || [ -L "$directory_path" ]; then
    printf 'error: expected directory path is not a real directory: %s\n' \
      "$directory_path" >&2
    exit 1
  fi
}

restore_directory_state() {
  directory_path=$1
  backup_name=$2
  if [ -e "$backup_dir/$backup_name.present" ]; then
    if [ -d "$directory_path" ] && [ ! -L "$directory_path" ]; then
      chmod "$(cat "$backup_dir/$backup_name.mode")" "$directory_path"
    fi
  else
    rmdir "$directory_path" 2>/dev/null || true
  fi
}

restore_file() {
  target_path=$1
  backup_name=$2
  if [ -e "$backup_dir/$backup_name.present" ]; then
    rm -f "$target_path"
    install -d -m 700 "$(dirname "$target_path")"
    cp -a "$backup_dir/$backup_name" "$target_path"
  else
    rm -f "$target_path"
  fi
}

paths_match() {
  left=$1
  right=$2
  if [ -L "$left" ] || [ -L "$right" ]; then
    [ -L "$left" ] && [ -L "$right" ] &&
      [ "$(readlink "$left")" = "$(readlink "$right")" ]
  elif [ -f "$left" ] || [ -f "$right" ]; then
    [ -f "$left" ] && [ -f "$right" ] && cmp -s "$left" "$right" &&
      [ "$(stat -c '%u:%g:%a' "$left")" = "$(stat -c '%u:%g:%a' "$right")" ]
  else
    [ ! -e "$left" ] && [ ! -e "$right" ]
  fi
}

restore_file_conditionally() {
  target_path=$1
  backup_name=$2
  installed_name=$3
  installed_path=$backup_dir/$installed_name
  if [ ! -e "$installed_path.present" ]; then
    return
  fi
  if paths_match "$target_path" "$installed_path"; then
    restore_file "$target_path" "$backup_name"
  else
    printf 'warning: preserved concurrent change during rollback: %s\n' \
      "$target_path" >&2
  fi
}

restore_managed_hook() {
  hook_name=$1
  target_path=$hooks_dir/$hook_name
  before_path=$backup_dir/global-hooks-before/$hook_name
  installed_path=$backup_dir/global-hooks-installed/$hook_name
  if paths_match "$target_path" "$installed_path"; then
    rm -f "$target_path"
    if [ -e "$before_path" ] || [ -L "$before_path" ]; then
      cp -a "$before_path" "$target_path"
    fi
  else
    printf 'warning: preserved concurrent hook change during rollback: %s\n' \
      "$target_path" >&2
  fi
}

restore_project_configs_conditionally() {
  [ -d "$backup_dir/project-configs-installed" ] || return
  python3 - "$project_config_list" \
    "$backup_dir/project-configs-before" \
    "$backup_dir/project-configs-installed" <<'PY'
from pathlib import Path
import os
import shutil
import sys
import tempfile

inventory, before_root, installed_root = map(Path, sys.argv[1:])

def same(left: Path, right: Path) -> bool:
    try:
        left_stat = left.stat()
        right_stat = right.stat()
        return (
            left.read_bytes() == right.read_bytes()
            and (left_stat.st_uid, left_stat.st_gid, left_stat.st_mode & 0o777)
            == (right_stat.st_uid, right_stat.st_gid, right_stat.st_mode & 0o777)
        )
    except FileNotFoundError:
        return not left.exists() and not right.exists()

for raw in inventory.read_bytes().split(b"\0"):
    if not raw:
        continue
    target = Path(os.fsdecode(raw))
    relative = target.relative_to("/")
    before = before_root / relative
    installed = installed_root / relative
    if not same(target, installed):
        print(f"warning: preserved concurrent Git config change: {target}", file=sys.stderr)
        continue
    if not before.exists():
        target.unlink(missing_ok=True)
        continue
    descriptor, temp_name = tempfile.mkstemp(prefix=f".{target.name}.rollback-", dir=target.parent)
    os.close(descriptor)
    temp = Path(temp_name)
    try:
        shutil.copy2(before, temp)
        os.replace(temp, target)
    finally:
        temp.unlink(missing_ok=True)
PY
}

restore_timer_state() {
  $systemd_user_available || return
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  case $timer_enabled_state in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      systemctl --user enable dev-policy-audit.timer >/dev/null 2>&1 || true
      ;;
    masked|masked-runtime)
      systemctl --user mask dev-policy-audit.timer >/dev/null 2>&1 || true
      ;;
    *)
      systemctl --user disable dev-policy-audit.timer >/dev/null 2>&1 || true
      ;;
  esac
  if [ "$timer_active_state" = active ]; then
    systemctl --user start dev-policy-audit.timer >/dev/null 2>&1 || true
  else
    systemctl --user stop dev-policy-audit.timer >/dev/null 2>&1 || true
  fi
}

rollback_install() {
  printf 'warning: installation failed; restoring backup %s\n' "$backup_dir" >&2
  restore_file_conditionally "$HOME/.codex/AGENTS.md" codex-AGENTS.md codex-AGENTS.installed
  restore_file_conditionally "$HOME/.codex/AGENTS.override.md" \
    codex-AGENTS.override.md codex-AGENTS.override.installed
  restore_file_conditionally "$HOME/.codex/config.toml" codex-config.toml codex-config.installed
  restore_file_conditionally "$HOME/.claude/CLAUDE.md" \
    claude-CLAUDE.md claude-CLAUDE.installed
  restore_file_conditionally "$HOME/Projects/AGENTS.md" \
    projects-AGENTS.md projects-AGENTS.installed
  restore_file_conditionally "$HOME/Projects/CLAUDE.md" \
    projects-CLAUDE.md projects-CLAUDE.installed
  restore_file_conditionally "$HOME/Projects/SERVER-DEVELOPMENT-CONSENSUS.md" \
    projects-consensus.md projects-consensus.installed
  restore_file_conditionally "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md" \
    projects-port-registry.md projects-port-registry.installed
  restore_file_conditionally "$HOME/.gitconfig" gitconfig gitconfig.installed
  restore_file_conditionally \
    "$HOME/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md" \
    installed-consensus.md installed-consensus.installed
  restore_file_conditionally \
    "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md" \
    installed-port-registry.md installed-port-registry.installed
  restore_file_conditionally \
    "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md" \
    installed-codex-policy.md installed-codex-policy.installed
  restore_file_conditionally \
    "$HOME/.config/server-development-consensus/managed-hooks.sha256" \
    installed-hooks-manifest installed-hooks-manifest.installed
  restore_file_conditionally \
    "$HOME/.local/lib/server-development-consensus/dev-git-common.sh" \
    installed-common.sh installed-common.installed
  restore_file_conditionally "$HOME/.local/bin/dev-start" \
    installed-dev-start installed-dev-start.installed
  restore_file_conditionally "$HOME/.local/bin/dev-pr" \
    installed-dev-pr installed-dev-pr.installed
  restore_file_conditionally "$HOME/.local/bin/dev-worktree" \
    installed-dev-worktree installed-dev-worktree.installed
  restore_file_conditionally "$HOME/.local/bin/dev-policy-audit" \
    installed-dev-policy-audit installed-dev-policy-audit.installed
  restore_file_conditionally "$HOME/.local/bin/dev-reap-sandbox" \
    installed-dev-reap-sandbox installed-dev-reap-sandbox.installed
  restore_file_conditionally "$HOME/.local/bin/dev-host" \
    installed-dev-host installed-dev-host.installed
  restore_file_conditionally "$HOME/.local/bin/hash-tree.sh" \
    installed-hash-tree installed-hash-tree.installed
  restore_file_conditionally "$HOME/.local/bin/update-codex-config" \
    installed-update-codex-config installed-update-codex-config.installed
  restore_file_conditionally "$HOME/.local/bin/sync-privileged-policy" \
    installed-privileged-sync installed-privileged-sync.installed
  restore_file_conditionally "$HOME/.config/systemd/user/dev-policy-audit.service" \
    installed-audit-service installed-audit-service.installed
  restore_file_conditionally "$HOME/.config/systemd/user/dev-policy-audit.timer" \
    installed-audit-timer installed-audit-timer.installed
  install -d -m 700 "$hooks_dir"
  restore_managed_hook hook-forwarder
  restore_managed_hook .managed-by-server-development-consensus
  while IFS= read -r hook; do
    restore_managed_hook "$hook"
  done <<EOF
$(git_hook_names)
EOF
  restore_project_configs_conditionally
  if [ -n "$created_chain_target" ]; then
    find "$created_chain_target" -mindepth 1 -delete 2>/dev/null || true
    rmdir "$created_chain_target" 2>/dev/null || true
  fi
  restore_timer_state
  restore_directory_state "$HOME/.config/systemd/user" systemd-user-dir
  restore_directory_state "$HOME/.claude" claude-dir
  restore_directory_state "$HOME/.codex" codex-dir
  restore_directory_state "$HOME/.local/bin" local-bin-dir
  restore_directory_state "$HOME/.local/lib/server-development-consensus" local-policy-lib-dir
  restore_directory_state "$hooks_dir" hooks-dir
  restore_directory_state "$policy_dir" policy-dir
  restore_directory_state "$HOME/Projects" projects-dir
}

cleanup() {
  status=$?
  trap - EXIT
  if $rollback_ready && ! $install_succeeded; then
    set +e
    rollback_install
    set -e
  fi
  rm -f "${project_config_list:-}"
  exit "$status"
}
trap cleanup EXIT

python3 "$base_dir/bin/update-codex-config" --check \
  "$HOME/.codex/config.toml" "$base_dir/CODEX-DEVELOPER-INSTRUCTIONS.md"

if previous_global_hooks=$(git config --global --path --get core.hooksPath 2>/dev/null); then
  previous_global_hooks_status=0
else
  previous_global_hooks_status=$?
fi
if [ "$previous_global_hooks_status" -gt 1 ]; then
  printf '%s\n' 'error: cannot inspect existing global core.hooksPath' >&2
  exit 1
fi
[ "$previous_global_hooks_status" -eq 0 ] || previous_global_hooks=

if previous_global_chain=$(git config --global --path --get serverPolicy.globalChainedHooksPath 2>/dev/null); then
  previous_global_chain_status=0
else
  previous_global_chain_status=$?
fi
if [ "$previous_global_chain_status" -gt 1 ]; then
  printf '%s\n' 'error: cannot inspect existing global chained hooks metadata' >&2
  exit 1
fi
[ "$previous_global_chain_status" -eq 0 ] || previous_global_chain=

# shellcheck disable=SC1090
. "$common_source"

canonical_directory() {
  directory=$1
  [ -d "$directory" ] || return 1
  CDPATH= cd -- "$directory" 2>/dev/null || return 1
  pwd -P
}

canonical_hooks_dir=$(canonical_directory "$hooks_dir" 2>/dev/null || printf '%s\n' "$hooks_dir")
known_legacy_policy_hook_pair() {
  commit_hash=$(sha256sum "$hooks_dir/pre-commit" | awk '{print $1}') || return 1
  push_hash=$(sha256sum "$hooks_dir/pre-push" | awk '{print $1}') || return 1
  case "$commit_hash $push_hash" in
    'd9321d6e4e9760be734df0b4d8d9668d545d0749b37d36fc719c904b87545151 e3f033b2b67ebf75a4a2ad424b12dd2ad291f5b4129390d9e34f69f214f71106'|\
    '8eafe0c5aa3017f855f16edc707ff8766550ca6721625a0cdec5b3c21eca1cd5 7465da427b0d77effe57801877bb1d95e6705360dcd3a8a5f0e814bab1a2f6f9'|\
    '594d82b528c9ff93d06826c643b66da754e0c76eff0ad31457127f7cc92836ed 3da02d37e49a402fa780bfdbf0b9d7b11d32dc87168b493c245c58a17c389579'|\
    'd946ba348ff56c0f228baa4e5960a4964ea9145a76f49682c1d034ee5e18bc8c d52a874b98e616dac38d7026212ef303b1fa512c0f40bec5087d76ec9366e1d3')
      return 0
      ;;
  esac
  return 1
}

known_legacy_pre_commit_hook() {
  hook_hash=$(sha256sum "$hooks_dir/pre-commit" | awk '{print $1}') || return 1
  case $hook_hash in
    d9321d6e4e9760be734df0b4d8d9668d545d0749b37d36fc719c904b87545151|\
    8eafe0c5aa3017f855f16edc707ff8766550ca6721625a0cdec5b3c21eca1cd5|\
    594d82b528c9ff93d06826c643b66da754e0c76eff0ad31457127f7cc92836ed|\
    d946ba348ff56c0f228baa4e5960a4964ea9145a76f49682c1d034ee5e18bc8c)
      return 0
      ;;
  esac
  return 1
}

known_legacy_pre_push_hook() {
  hook_hash=$(sha256sum "$hooks_dir/pre-push" | awk '{print $1}') || return 1
  case $hook_hash in
    e3f033b2b67ebf75a4a2ad424b12dd2ad291f5b4129390d9e34f69f214f71106|\
    7465da427b0d77effe57801877bb1d95e6705360dcd3a8a5f0e814bab1a2f6f9|\
    3da02d37e49a402fa780bfdbf0b9d7b11d32dc87168b493c245c58a17c389579|\
    d52a874b98e616dac38d7026212ef303b1fa512c0f40bec5087d76ec9366e1d3)
      return 0
      ;;
  esac
  return 1
}

managed_forwarder_layout_matches() {
  [ -x "$hooks_dir/hook-forwarder" ] || return 1
  while IFS= read -r hook; do
    case $hook in
      pre-commit|pre-merge-commit|pre-push|commit-msg) continue ;;
    esac
    [ -L "$hooks_dir/$hook" ] || return 1
    [ "$(readlink "$hooks_dir/$hook")" = hook-forwarder ] || return 1
  done <<EOF
$(git_hook_names)
EOF
}

preserve_managed_hooks_as_chain() {
  previous_chain_target=$chain_target
  new_chain_target=$HOME/.config/server-development-consensus/chained-global-hooks/$timestamp
  created_chain_target=$new_chain_target
  install -d -m 700 "$new_chain_target"
  cp -a "$hooks_dir/." "$new_chain_target/"
  rm -f "$new_chain_target/.managed-by-server-development-consensus" \
    "$new_chain_target/hook-forwarder"
  while IFS= read -r hook; do
    case $hook in
      pre-commit)
        $pre_commit_hook_known && rm -f "$new_chain_target/$hook"
        ;;
      pre-push)
        $pre_push_hook_known && rm -f "$new_chain_target/$hook"
        ;;
      pre-merge-commit)
        $pre_merge_hook_known && rm -f "$new_chain_target/$hook"
        ;;
      commit-msg)
        $commit_msg_hook_known && rm -f "$new_chain_target/$hook"
        ;;
      *)
        if [ -L "$new_chain_target/$hook" ] &&
           [ "$(readlink "$new_chain_target/$hook")" = hook-forwarder ]; then
          rm -f "$new_chain_target/$hook"
        fi
        ;;
    esac
  done <<EOF
$(git_hook_names)
EOF
  if [ -n "$previous_chain_target" ]; then
    cp -a -n "$previous_chain_target/." "$new_chain_target/"
  fi
  chain_target=$new_chain_target
}

if [ -n "$previous_global_chain" ]; then
  case $previous_global_chain in
    /*) ;;
    *)
      printf '%s\n' 'error: global chained hooks path must be absolute' >&2
      exit 1
      ;;
  esac
  canonical_previous_chain=$(canonical_directory "$previous_global_chain") || {
    printf 'error: global chained hooks path is unavailable: %s\n' "$previous_global_chain" >&2
    exit 1
  }
  if [ "$canonical_previous_chain" = "$canonical_hooks_dir" ]; then
    printf '%s\n' 'error: global chained hooks path points to the managed hooks directory' >&2
    exit 1
  fi
fi

legacy_policy_hooks=false
managed_hook_manifest_matches=false
if [ -f "$hooks_dir/.managed-by-server-development-consensus" ] &&
   [ ! -L "$hooks_dir/.managed-by-server-development-consensus" ] &&
   [ -f "$policy_dir/managed-hooks.sha256" ] &&
   [ ! -L "$policy_dir/managed-hooks.sha256" ] &&
   (cd "$hooks_dir" &&
     sha256sum --check --status "$policy_dir/managed-hooks.sha256"); then
  managed_hook_manifest_matches=true
fi
pre_commit_hook_known=false
if cmp -s "$hooks_dir/pre-commit" "$base_dir/git-hooks/pre-commit" ||
   known_legacy_pre_commit_hook; then
  pre_commit_hook_known=true
fi
pre_push_hook_known=false
if cmp -s "$hooks_dir/pre-push" "$base_dir/git-hooks/pre-push" ||
   known_legacy_pre_push_hook; then
  pre_push_hook_known=true
fi
policy_hook_pair_known=false
if [ -x "$hooks_dir/pre-commit" ] && [ -x "$hooks_dir/pre-push" ] &&
   { { cmp -s "$hooks_dir/pre-commit" "$base_dir/git-hooks/pre-commit" &&
       cmp -s "$hooks_dir/pre-push" "$base_dir/git-hooks/pre-push"; } ||
     known_legacy_policy_hook_pair; }; then
  policy_hook_pair_known=true
fi
pre_merge_hook_known=false
if cmp -s "$hooks_dir/pre-merge-commit" "$base_dir/git-hooks/pre-merge-commit" ||
   { [ -L "$hooks_dir/pre-merge-commit" ] &&
     [ "$(readlink "$hooks_dir/pre-merge-commit")" = hook-forwarder ]; }; then
  pre_merge_hook_known=true
fi
commit_msg_hook_known=false
if cmp -s "$hooks_dir/commit-msg" "$base_dir/git-hooks/commit-msg" ||
   { [ -L "$hooks_dir/commit-msg" ] &&
     [ "$(readlink "$hooks_dir/commit-msg")" = hook-forwarder ]; }; then
  commit_msg_hook_known=true
fi
if { $managed_hook_manifest_matches ||
     { $policy_hook_pair_known && $pre_merge_hook_known; }; } &&
   managed_forwarder_layout_matches; then
  legacy_policy_hooks=true
fi

install -d -m 700 "$backup_dir"
backup_directory_state "$HOME/Projects" projects-dir
backup_directory_state "$policy_dir" policy-dir
backup_directory_state "$hooks_dir" hooks-dir
backup_directory_state "$HOME/.local/lib/server-development-consensus" local-policy-lib-dir
backup_directory_state "$HOME/.local/bin" local-bin-dir
backup_directory_state "$HOME/.codex" codex-dir
backup_directory_state "$HOME/.claude" claude-dir
backup_directory_state "$HOME/.config/systemd/user" systemd-user-dir
backup_file "$HOME/.codex/AGENTS.md" codex-AGENTS.md
backup_file "$HOME/.codex/AGENTS.override.md" codex-AGENTS.override.md
backup_file "$HOME/.codex/config.toml" codex-config.toml
backup_file "$HOME/.claude/CLAUDE.md" claude-CLAUDE.md
backup_file "$HOME/Projects/AGENTS.md" projects-AGENTS.md
backup_file "$HOME/Projects/CLAUDE.md" projects-CLAUDE.md
backup_file "$HOME/Projects/SERVER-DEVELOPMENT-CONSENSUS.md" projects-consensus.md
backup_file "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md" projects-port-registry.md
backup_file "$HOME/.gitconfig" gitconfig
backup_file "$HOME/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md" installed-consensus.md
backup_file "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md" installed-port-registry.md
backup_file "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md" installed-codex-policy.md
backup_file "$HOME/.config/server-development-consensus/managed-hooks.sha256" installed-hooks-manifest
backup_file "$HOME/.local/lib/server-development-consensus/dev-git-common.sh" installed-common.sh
backup_file "$HOME/.local/bin/dev-start" installed-dev-start
backup_file "$HOME/.local/bin/dev-pr" installed-dev-pr
backup_file "$HOME/.local/bin/dev-worktree" installed-dev-worktree
backup_file "$HOME/.local/bin/dev-policy-audit" installed-dev-policy-audit
backup_file "$HOME/.local/bin/dev-reap-sandbox" installed-dev-reap-sandbox
backup_file "$HOME/.local/bin/dev-host" installed-dev-host
backup_file "$HOME/.local/bin/hash-tree.sh" installed-hash-tree
backup_file "$HOME/.local/bin/update-codex-config" installed-update-codex-config
backup_file "$HOME/.local/bin/sync-privileged-policy" installed-privileged-sync
backup_file "$HOME/.config/systemd/user/dev-policy-audit.service" installed-audit-service
backup_file "$HOME/.config/systemd/user/dev-policy-audit.timer" installed-audit-timer
install -d -m 700 "$backup_dir/global-hooks-before"
if [ -d "$hooks_dir" ]; then
  cp -a "$hooks_dir/." "$backup_dir/global-hooks-before/"
fi
rollback_ready=true
install -d -m 750 "$HOME/Projects"
project_config_list=$(mktemp)
if ! find_project_git_configs "$HOME/Projects" >"$project_config_list"; then
  printf '%s\n' 'error: could not inventory project Git configuration files' >&2
  exit 1
fi
tar --null -czf "$backup_dir/project-git-configs.tar.gz" --files-from "$project_config_list"
install -d -m 700 "$backup_dir/project-configs-before"
tar -C "$backup_dir/project-configs-before" \
  -xzf "$backup_dir/project-git-configs.tar.gz"

chain_target=$previous_global_chain
if [ -n "$previous_global_hooks" ]; then
  case $previous_global_hooks in
    /*) ;;
    *)
      printf '%s\n' 'error: existing global core.hooksPath must be absolute before migration' >&2
      exit 1
      ;;
  esac
  canonical_previous_hooks=$(canonical_directory "$previous_global_hooks") || {
    printf 'error: existing global core.hooksPath is unavailable: %s\n' "$previous_global_hooks" >&2
    exit 1
  }
  if [ "$canonical_previous_hooks" != "$canonical_hooks_dir" ]; then
    chain_target=$canonical_previous_hooks
  elif ! $legacy_policy_hooks; then
    existing_hook=false
    while IFS= read -r hook; do
      if [ -x "$hooks_dir/$hook" ]; then
        existing_hook=true
        break
      fi
    done <<EOF
$(git_hook_names)
EOF
    $existing_hook && preserve_managed_hooks_as_chain
  fi
elif [ -d "$hooks_dir" ] && [ ! -e "$hooks_dir/.managed-by-server-development-consensus" ] &&
     ! $legacy_policy_hooks; then
  existing_hook=false
  while IFS= read -r hook; do
    if [ -x "$hooks_dir/$hook" ]; then
      existing_hook=true
      break
    fi
  done <<EOF
$(git_hook_names)
EOF
  if $existing_hook; then
    preserve_managed_hooks_as_chain
  fi
fi
if [ -n "$chain_target" ]; then
  canonical_chain_target=$(canonical_directory "$chain_target") || {
    printf 'error: chained hooks target is unavailable: %s\n' "$chain_target" >&2
    exit 1
  }
  if [ "$canonical_chain_target" = "$canonical_hooks_dir" ]; then
    printf '%s\n' 'error: chained hooks target points to the managed hooks directory' >&2
    exit 1
  fi
  chain_target=$canonical_chain_target
fi

install -d -m 700 "$policy_dir"
install -d -m 700 "$hooks_dir"
install -d -m 700 "$HOME/.local/lib/server-development-consensus"
install -d -m 700 "$HOME/.local/bin"
install -d -m 700 "$HOME/.codex" "$HOME/.claude"
install -d -m 700 "$HOME/.config/systemd/user"

install -m 600 "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" \
  "$HOME/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md"
backup_file "$HOME/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md" \
  installed-consensus.installed
install -m 600 "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" \
  "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md"
backup_file "$HOME/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md" \
  installed-port-registry.installed
install -m 600 "$base_dir/CODEX-DEVELOPER-INSTRUCTIONS.md" \
  "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md"
backup_file "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md" \
  installed-codex-policy.installed
install -m 640 "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$HOME/Projects/AGENTS.md"
backup_file "$HOME/Projects/AGENTS.md" projects-AGENTS.installed
install -m 640 "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$HOME/Projects/CLAUDE.md"
backup_file "$HOME/Projects/CLAUDE.md" projects-CLAUDE.installed
install -m 640 "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" \
  "$HOME/Projects/SERVER-DEVELOPMENT-CONSENSUS.md"
backup_file "$HOME/Projects/SERVER-DEVELOPMENT-CONSENSUS.md" projects-consensus.installed
install -m 640 "$base_dir/DEVELOPMENT-PORT-REGISTRY.md" \
  "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md"
backup_file "$HOME/Projects/DEVELOPMENT-PORT-REGISTRY.md" projects-port-registry.installed

for global_agent_file in \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.codex/AGENTS.override.md" \
  "$HOME/.claude/CLAUDE.md"; do
  if [ ! -e "$global_agent_file" ] || [ -w "$global_agent_file" ]; then
    install -m 600 "$base_dir/SERVER-DEVELOPMENT-CONSENSUS.md" "$global_agent_file"
    case $global_agent_file in
      "$HOME/.codex/AGENTS.md")
        backup_file "$global_agent_file" codex-AGENTS.installed
        ;;
      "$HOME/.codex/AGENTS.override.md")
        backup_file "$global_agent_file" codex-AGENTS.override.installed
        ;;
      "$HOME/.claude/CLAUDE.md")
        backup_file "$global_agent_file" claude-CLAUDE.installed
        ;;
    esac
  else
    printf 'notice: preserved root-maintained global agent file: %s\n' "$global_agent_file"
  fi
done

install -m 600 "$common_source" \
  "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
backup_file "$HOME/.local/lib/server-development-consensus/dev-git-common.sh" \
  installed-common.installed
install -m 700 "$base_dir/git-hooks/hook-forwarder" "$hooks_dir/hook-forwarder"
while IFS= read -r hook; do
  case $hook in
    pre-commit|pre-merge-commit|pre-push|commit-msg) ;;
    *) ln -sfn hook-forwarder "$hooks_dir/$hook" ;;
  esac
done <<EOF
$(git_hook_names)
EOF
install -m 700 "$base_dir/git-hooks/pre-push" "$hooks_dir/pre-push"
install -m 700 "$base_dir/git-hooks/pre-commit" "$hooks_dir/pre-commit"
install -m 700 "$base_dir/git-hooks/pre-merge-commit" "$hooks_dir/pre-merge-commit"
install -m 700 "$base_dir/git-hooks/commit-msg" "$hooks_dir/commit-msg"
: >"$hooks_dir/.managed-by-server-development-consensus"
chmod 600 "$hooks_dir/.managed-by-server-development-consensus"
hooks_manifest_temp=$policy_dir/managed-hooks.sha256.tmp.$$
(
  cd "$hooks_dir"
  sha256sum hook-forwarder pre-commit pre-merge-commit pre-push commit-msg
) >"$hooks_manifest_temp"
chmod 600 "$hooks_manifest_temp"
mv -f "$hooks_manifest_temp" "$policy_dir/managed-hooks.sha256"
backup_file "$policy_dir/managed-hooks.sha256" installed-hooks-manifest.installed

install -m 700 "$base_dir/bin/dev-start" "$HOME/.local/bin/dev-start"
backup_file "$HOME/.local/bin/dev-start" installed-dev-start.installed
install -m 700 "$base_dir/bin/dev-pr" "$HOME/.local/bin/dev-pr"
backup_file "$HOME/.local/bin/dev-pr" installed-dev-pr.installed
install -m 700 "$base_dir/bin/dev-worktree" "$HOME/.local/bin/dev-worktree"
backup_file "$HOME/.local/bin/dev-worktree" installed-dev-worktree.installed
install -m 700 "$base_dir/bin/dev-policy-audit" "$HOME/.local/bin/dev-policy-audit"
install -m 700 "$base_dir/bin/dev-reap-sandbox" "$HOME/.local/bin/dev-reap-sandbox"
backup_file "$HOME/.local/bin/dev-policy-audit" installed-dev-policy-audit.installed
install -m 700 "$base_dir/bin/dev-host" "$HOME/.local/bin/dev-host"
backup_file "$HOME/.local/bin/dev-host" installed-dev-host.installed
install -m 700 "$base_dir/bin/hash-tree.sh" "$HOME/.local/bin/hash-tree.sh"
backup_file "$HOME/.local/bin/hash-tree.sh" installed-hash-tree.installed
install -m 700 "$base_dir/bin/update-codex-config" "$HOME/.local/bin/update-codex-config"
backup_file "$HOME/.local/bin/update-codex-config" installed-update-codex-config.installed
install -m 700 "$base_dir/bin/sync-privileged-policy" \
  "$HOME/.local/bin/sync-privileged-policy"
backup_file "$HOME/.local/bin/sync-privileged-policy" installed-privileged-sync.installed
install -m 600 "$base_dir/systemd/dev-policy-audit.service" \
  "$HOME/.config/systemd/user/dev-policy-audit.service"
backup_file "$HOME/.config/systemd/user/dev-policy-audit.service" \
  installed-audit-service.installed
install -m 600 "$base_dir/systemd/dev-policy-audit.timer" \
  "$HOME/.config/systemd/user/dev-policy-audit.timer"
backup_file "$HOME/.config/systemd/user/dev-policy-audit.timer" \
  installed-audit-timer.installed

install -d -m 700 "$backup_dir/global-hooks-installed"
cp -a "$hooks_dir/." "$backup_dir/global-hooks-installed/"

if [ "${SERVER_POLICY_INSTALL_FAIL_STAGE:-}" = after-files ]; then
  printf '%s\n' 'error: injected installation failure after files' >&2
  exit 1
fi

python3 "$HOME/.local/bin/update-codex-config" \
  "$HOME/.codex/config.toml" \
  "$HOME/.config/server-development-consensus/CODEX-DEVELOPER-INSTRUCTIONS.md"
backup_file "$HOME/.codex/config.toml" codex-config.installed

if [ -n "$chain_target" ]; then
  git config --global serverPolicy.globalChainedHooksPath "$chain_target"
else
  git config --global --unset-all serverPolicy.globalChainedHooksPath >/dev/null 2>&1 || true
fi
git_config_status=0
git config --global core.hooksPath "$hooks_dir" || git_config_status=1
git config --global init.defaultBranch main || git_config_status=1
git config --global pull.ff only || git_config_status=1
git config --global fetch.prune true || git_config_status=1
git config --global push.default simple || git_config_status=1
git config --global commit.verbose true || git_config_status=1
backup_file "$HOME/.gitconfig" gitconfig.installed
if [ "$git_config_status" -ne 0 ]; then
  printf '%s\n' 'error: could not write managed global Git configuration' >&2
  exit 1
fi
if [ "${SERVER_POLICY_INSTALL_FAIL_STAGE:-}" = after-git-config ]; then
  printf '%s\n' 'error: injected installation failure after Git config' >&2
  exit 1
fi

set +e
SERVER_POLICY_CONFIG_LOCK_HELD=1 SERVER_POLICY_HOME=$HOME \
  "$HOME/.local/bin/dev-policy-audit" --repair "$HOME/Projects"
audit_status=$?
set -e
install -d -m 700 "$backup_dir/project-configs-installed"
tar --null -czf "$backup_dir/project-git-configs-installed.tar.gz" \
  --files-from "$project_config_list"
tar -C "$backup_dir/project-configs-installed" \
  -xzf "$backup_dir/project-git-configs-installed.tar.gz"
if [ "$audit_status" -ne 0 ]; then
  printf '%s\n' 'error: server development policy audit repair failed' >&2
  exit "$audit_status"
fi
if $systemd_user_available; then
  systemctl --user daemon-reload
  systemctl --user enable --now dev-policy-audit.timer
else
  printf '%s\n' 'warning: systemd user manager unavailable; timer installed but not enabled' >&2
fi
if [ "${SERVER_POLICY_INSTALL_FAIL_STAGE:-}" = after-systemd ]; then
  printf '%s\n' 'error: injected installation failure after systemd enablement' >&2
  exit 1
fi
install_succeeded=true
printf 'server development consensus installed; backup=%s\n' "$backup_dir"
