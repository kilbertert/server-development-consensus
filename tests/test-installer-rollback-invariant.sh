#!/usr/bin/env bash
# The installer's rollback is a claim about the host: after it runs, every file
# it manages is back in the state it was in before the run.
#
# Two defects used to break that claim together, and either one alone is enough
# to delete a managed tool on the failure path:
#
#   - the ".installed" snapshot was taken AFTER the write, so it recorded the
#     new content and the rollback had nothing older to put back;
#   - some restore calls named a snapshot that was never written, and a missing
#     ".present" marker makes the restore return silently as "nothing to undo".
#
# This exercises the pieces in isolation rather than running the whole
# installer, which needs systemd, network git remotes, and a host-shaped HOME.
set -euo pipefail

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

extract_function() {
  local name=$1
  awk -v fn="$name" '
    $0 ~ "^" fn "\\(\\) \\{" { printing = 1 }
    printing { print }
    printing && /^\}$/ { exit }
  ' "$base_dir/install.sh"
}

backup_dir=$tmp/backups
mkdir -p "$backup_dir"
die() { printf '%s\n' "$*" >&2; exit 1; }
eval "$(extract_function backup_file)"
eval "$(extract_function restore_file)"
eval "$(extract_function paths_match)"
eval "$(extract_function restore_file_conditionally)"
eval "$(extract_function verify_rollback_invariant)"

managed=$tmp/home/.local/bin/dev-tool
mkdir -p "$(dirname "$managed")"
printf '%s\n' 'previous version' >"$managed"
chmod 750 "$managed"

# The install step end to end, mirroring the installer's two snapshots:
#   - the pre-install state, restored by a rollback;
#   - the post-install state, so the rollback can tell its own output from a
#     concurrent edit.
backup_file "$managed" installed-dev-tool
printf '%s\n' 'new version' >"$managed"
chmod 750 "$managed"
backup_file "$managed" installed-dev-tool.installed

# The snapshot must describe the PRE-install state. Snapshotting after the write
# records the new content as if it were the old one, so rollback "restores" a
# half-installed host and reports success.
if ! grep -q 'previous version' "$backup_dir/installed-dev-tool"; then
  printf '%s\n' 'FAIL pre-install snapshot captured the new content, not the old' >&2
  exit 1
fi
if ! grep -q 'new version' "$backup_dir/installed-dev-tool.installed"; then
  printf '%s\n' 'FAIL post-install snapshot does not describe what this run wrote' >&2
  exit 1
fi

# The rollback restores the old content and leaves the tool usable.
restore_file_conditionally "$managed" installed-dev-tool installed-dev-tool.installed
if ! grep -q 'previous version' "$managed"; then
  printf '%s\n' 'FAIL rollback did not restore the pre-install content' >&2
  exit 1
fi
[ -x "$managed" ]
if ! verify_rollback_invariant "$managed:installed-dev-tool.installed"; then
  printf '%s\n' 'FAIL invariant rejected a correct rollback' >&2
  exit 1
fi

# The regression: a restore call naming a snapshot that was never written
# returns silently and the tool is gone. The invariant must catch that instead
# of letting the installer report a clean rollback.
rm -f "$managed"
if verify_rollback_invariant "$managed:installed-dev-tool.installed" 2>"$tmp/inv.err"; then
  printf '%s\n' 'FAIL invariant accepted a lost managed tool' >&2
  exit 1
fi
grep -q 'rollback lost a managed file' "$tmp/inv.err"

# A file that did not exist before the run is correctly absent afterwards: its
# snapshot carries no ".present" marker, so absence is not a violation.
if ! verify_rollback_invariant "$tmp/home/.local/bin/never-existed:installed-never-existed.installed"; then
  printf '%s\n' 'FAIL invariant rejected a correctly-absent file' >&2
  exit 1
fi

# A managed tool left non-executable is present but unusable: existence alone
# reads as success and hides it.
noexec=$tmp/home/.local/bin/dev-tool-noexec
printf '%s\n' 'restored' >"$noexec"
chmod 640 "$noexec"
if verify_rollback_invariant "$noexec:installed-dev-tool.installed" 2>"$tmp/inv2.err"; then
  printf '%s\n' 'FAIL invariant accepted a non-executable managed tool' >&2
  exit 1
fi
grep -q 'not executable' "$tmp/inv2.err"

printf '%s\n' 'installer rollback invariant: ok'
