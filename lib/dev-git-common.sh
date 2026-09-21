#!/bin/sh

is_valid_branch_name() (
  [ -n "${1:-}" ] || return 1
  case $1 in
    refs/*) return 1 ;;
  esac
  normalized=$(git check-ref-format --branch "$1" 2>/dev/null) || return 1
  [ "$normalized" = "$1" ]
)

# Repository class. A repository whose delivery process is owned by another
# organization is marked `external` in its own local configuration; the server
# policy then keeps only the rules that describe this host. The marker lives in
# the repository, so the policy needs no host list, and the default is
# `managed` so an unreadable or unknown value can never widen an exemption.
repository_class() (
  repository_class_value=managed
  if configured_class=$(git config --local --get serverPolicy.repositoryClass 2>/dev/null); then
    repository_class_value=$configured_class
  else
    repository_class_status=$?
    [ "$repository_class_status" -eq 1 ] || return 2
  fi
  case $repository_class_value in
    managed|external) printf '%s\n' "$repository_class_value" ;;
    *) return 2 ;;
  esac
)

# Run the repository's own chained hook and hand it control. Used by externally
# governed repositories, which keep their own delivery process and hooks.
forward_to_chained_hook() {
  forward_hook_name=$1
  shift
  if chained_hook=$(chained_hook_for "$forward_hook_name"); then
    if paths_identify_same_file "$0" "$chained_hook"; then
      printf 'error: chained %s hook resolves to the managed hook; operation stopped safely.\n' \
        "$forward_hook_name" >&2
      return 1
    else
      same_status=$?
      [ "$same_status" -eq 1 ] || {
        printf 'error: cannot validate the chained %s hook; operation stopped safely.\n' \
          "$forward_hook_name" >&2
        return 1
      }
    fi
    exec "$chained_hook" "$@"
  else
    chained_status=$?
    [ "$chained_status" -eq 1 ] || {
      printf 'error: cannot resolve the chained %s hook; operation stopped safely.\n' \
        "$forward_hook_name" >&2
      return 1
    }
  fi
  return 0
}

git_hook_names() {
  printf '%s\n' \
    applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit \
    prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge \
    pre-push pre-receive update proc-receive post-receive post-update \
    reference-transaction push-to-checkout pre-auto-gc post-rewrite \
    sendemail-validate fsmonitor-watchman p4-changelist p4-prepare-changelist \
    p4-post-changelist p4-pre-submit post-index-change
}

find_project_git_entries() (
  projects_root=$1
  find "$projects_root" \
    \( -type d ! -readable -o -type d \
      \( -name .cache -o -name .uv-cache -o -name .venv -o -name venv -o \
         -name node_modules -o -name vendor -o -name dist -o -name build -o \
         -name .tox -o -name .nox -o -name __pycache__ -o \
         -name .pytest_cache -o -name .agent-private -o \
         -path '*/docker/volumes' \) \) -prune -o \
    -name .git -prune -print0
)

find_project_git_configs() (
  projects_root=$1
  entries=$(mktemp) || exit 1
  configs=$(mktemp) || {
    rm -f "$entries"
    exit 1
  }
  trap 'rm -f "$entries" "$configs"' EXIT
  find_project_git_entries "$projects_root" >"$entries" || exit 1
  xargs -0 -r -n1 sh -c '
    repo=${1%/.git}
    config=$(git -C "$repo" rev-parse --path-format=absolute --git-path config) || exit 1
    printf "%s\0" "$config"
  ' sh <"$entries" >"$configs" || exit 1
  sort -zu "$configs"
)

# A self-hosted runner checks code out in its own working directory for the
# duration of a job, and a standby or deploy checkout is written by a
# deployment rather than by this host's delivery flow. Both are deployment
# artifacts, not delivery surfaces: the policy already places them under the
# `_runners/` functional directory, and the installer never manages them. An
# audit that holds them to the managed-repository rules fails at random,
# depending on whether a job happened to be running. The caller passes an
# absolute path.
runner_checkout_path() {
  case "$(realpath -m -- "$1")/" in
    "$(realpath -m -- "${HOME:-}/Projects")/_runners/"*) return 0 ;;
    */_work/*) return 0 ;;
  esac
  return 1
}

default_branch_for_remote() (
  remote_name=${1:-origin}
  configured_default=
  configured_status=1

  if [ "${SERVER_POLICY_IGNORE_CONFIG:-0}" != 1 ] && [ "$remote_name" = origin ]; then
    if configured_default=$(git config --local --get serverPolicy.defaultBranch 2>/dev/null); then
      is_valid_branch_name "$configured_default" || return 1
      configured_status=0
    else
      config_status=$?
      [ "$config_status" -eq 1 ] || return 1
    fi
  fi

  if remote_url=$(git remote get-url "$remote_name" 2>/dev/null); then
    remote_head=$(git symbolic-ref --quiet --short "refs/remotes/$remote_name/HEAD" 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
      remote_default=${remote_head#"$remote_name/"}
      is_valid_branch_name "$remote_default" || return 1
      if git show-ref --verify --quiet "refs/remotes/$remote_name/$remote_default"; then
        [ "$configured_status" -ne 0 ] || [ "$configured_default" = "$remote_default" ] ||
          return 1
        printf '%s\n' "$remote_default"
        return 0
      fi
    fi

    github_repo=$(printf '%s\n' "$remote_url" |
      sed -nE 's#^(https?://|ssh://git@|git@)github\.com[/:]([^/]+/[^/]+)(\.git)?$#\2#p' |
      sed 's/\.git$//')
    if [ -n "$github_repo" ] && command -v gh >/dev/null 2>&1; then
      github_default=$(gh api "repos/$github_repo" --jq .default_branch 2>/dev/null || true)
      if is_valid_branch_name "$github_default"; then
        [ "$configured_status" -ne 0 ] || [ "$configured_default" = "$github_default" ] ||
          return 1
        printf '%s\n' "$github_default"
        return 0
      fi
    fi

    for candidate in main master; do
      if git show-ref --verify --quiet "refs/remotes/$remote_name/$candidate"; then
        [ "$configured_status" -ne 0 ] || [ "$configured_default" = "$candidate" ] ||
          return 1
        printf '%s\n' "$candidate"
        return 0
      fi
    done
    return 1
  fi

  init_default=$(git config --get init.defaultBranch 2>/dev/null || true)
  if is_valid_branch_name "$init_default"; then
    [ "$configured_status" -ne 0 ] || [ "$configured_default" = "$init_default" ] ||
      return 1
    printf '%s\n' "$init_default"
    return 0
  fi

  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate" ||
       [ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = "$candidate" ]; then
      [ "$configured_status" -ne 0 ] || [ "$configured_default" = "$candidate" ] ||
        return 1
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
)

default_branch_for_url() (
  remote_url=${1:-}
  [ -n "$remote_url" ] || return 1
  remote_default=$(git ls-remote --symref "$remote_url" HEAD 2>/dev/null |
    awk '$1 == "ref:" && $3 == "HEAD" {
      sub(/^refs\/heads\//, "", $2)
      print $2
      exit
    }') || return 1
  is_valid_branch_name "$remote_default" || return 1
  printf '%s\n' "$remote_default"
)

enforce_default_branch_commit_policy() {
  current_branch=$(git branch --show-current) || {
    printf '%s\n' 'SERVER POLICY: cannot determine the current branch; commit stopped safely.' >&2
    return 1
  }
  [ -n "$current_branch" ] || {
    printf '%s\n' 'SERVER POLICY: detached HEAD commits are prohibited; create a task branch first.' >&2
    return 1
  }

  default_branch=$(default_branch_for_remote origin) || {
    printf '%s\n' 'SERVER POLICY: cannot determine the default branch; commit stopped safely.' >&2
    printf '%s\n' 'Run dev-policy-audit --repair before retrying.' >&2
    return 1
  }

  if [ "$current_branch" = "$default_branch" ]; then
    printf '\n%s\n' 'SERVER POLICY: commits on the default branch are prohibited.' >&2
    printf 'Current branch: %s\n' "$current_branch" >&2
    printf '%s\n' 'Preserve the work on a task branch before committing.' >&2
    printf '%s\n' 'Use: dev-start TYPE DESCRIPTION' >&2
    return 1
  fi
}

resolve_hooks_path() (
  hooks_path=$1
  case $hooks_path in
    ~/*) resolved_path=$HOME/${hooks_path#~/} ;;
    /*) resolved_path=$hooks_path ;;
    *) resolved_path=$(git rev-parse --show-toplevel)/$hooks_path ;;
  esac
  [ -d "$resolved_path" ] || return 2
  CDPATH= cd -- "$resolved_path" 2>/dev/null || return 2
  pwd -P
)

chained_hook_for() (
  hook_name=$1
  if project_chain=$(git config --local --path --get serverPolicy.chainedHooksPath 2>/dev/null); then
    project_status=0
  else
    project_status=$?
  fi
  if [ "$project_status" -eq 0 ]; then
    [ -n "$project_chain" ] || return 2
    chain_path=$(resolve_hooks_path "$project_chain") || return 2
  elif [ "$project_status" -ne 1 ] &&
       git rev-parse --git-dir >/dev/null 2>&1; then
    # A real repository whose local config cannot be read is unsafe. Git 2.54
    # also invokes reference-transaction during `git init`, before a repository
    # context exists; that case legitimately has no project chain yet.
    return 2
  elif global_chain=$(git config --global --path --get serverPolicy.globalChainedHooksPath 2>/dev/null); then
    [ -n "$global_chain" ] || return 2
    chain_path=$(resolve_hooks_path "$global_chain") || return 2
  else
    global_status=$?
    [ "$global_status" -eq 1 ] || return 2
    return 1
  fi

  candidate=$chain_path/$hook_name
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    [ -x "$candidate" ] || return 2
  else
    return 1
  fi
  printf '%s\n' "$candidate"
)

paths_resolve_same() (
  left=$(readlink -f -- "$1" 2>/dev/null) || return 2
  right=$(readlink -f -- "$2" 2>/dev/null) || return 2
  [ "$left" = "$right" ]
)

paths_identify_same_file() {
  if paths_resolve_same "$1" "$2"; then
    return 0
  else
    resolve_status=$?
  fi
  [ "$resolve_status" -eq 1 ] || return "$resolve_status"
  [ "$1" -ef "$2" ]
}

require_repository() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' 'error: this command must run inside a Git worktree' >&2
    exit 2
  fi
}

require_clean_worktree() {
  worktree_status=$(git status --porcelain) || {
    printf '%s\n' 'error: could not inspect the worktree state' >&2
    exit 2
  }
  if [ -n "$worktree_status" ]; then
    printf '%s\n' 'error: the worktree is not clean; preserve or commit existing work before starting another task' >&2
    exit 2
  fi
}
