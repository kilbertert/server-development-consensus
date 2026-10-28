#!/usr/bin/env bash
# Structural guard: every `restore_file_conditionally <path> <before> <installed>`
# must name snapshots that some `backup_file` actually writes for that path.
#
# This is the defect that deleted two audit tools from a real host: the restore
# asked for "installed-dev-host-auth-audit" while the backup was written as
# "installed-dev-host-auth-audit.installed". A missing ".present" marker makes
# the restore return silently as "nothing to undo", so nothing failed - the tool
# was simply gone after a rollback that reported success.
#
# The runtime rollback invariant catches this on the failure path; this catches
# it at review time, before any failure path is ever exercised.
set -euo pipefail

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
python3 - "$base_dir/install.sh" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
# Join backslash continuations so a call spread over lines reads as one line.
joined = re.sub(r"\\\n\s*", " ", text)

def normalize(path):
    """Resolve the two variables the script uses to spell a directory, so the
    same file matches whether it is written as $HOME/... or $policy_dir/....
    Without this, `$policy_dir/x` and `$HOME/.config/server-development-consensus/x`
    look like different files and every cross-spelling call reads as missing."""
    path = path.replace(
        "$policy_dir", "$HOME/.config/server-development-consensus")
    path = path.replace("$hooks_dir", "$HOME/.config/git/hooks")
    return path

backups = re.findall(r'backup_file\s+"?([^"\s]+)"?\s+(\S+)', joined)
restores = re.findall(
    r'restore_file_conditionally\s+"?([^"\s]+)"?\s+(\S+)\s+(\S+)', joined)

# A backup written through the loop variable belongs to whichever concrete path
# its `case` arm names. Collect those, so the loop form is checked like any
# other call instead of being skipped - skipping was what let the original
# mismatch through the first version of this guard.
loop_backups = {}
for match in re.finditer(
        r'"(?P<path>\$HOME/[^"]+)"\)\s*\n\s*backup_file\s+"\$global_agent_file"\s+'
        r'(?P<snapshot>\S+)', text):
    loop_backups.setdefault(normalize(match.group("path")), set()).add(
        match.group("snapshot"))

sources = {}
for path, snapshot in backups:
    key = normalize(path)
    if key == "$global_agent_file":
        continue
    sources.setdefault(key, set()).add(snapshot)
for path, snapshots in loop_backups.items():
    sources.setdefault(path, set()).update(snapshots)

problems = []
for path, before, installed in restores:
    key = normalize(path)
    if key == "$global_agent_file":
        continue
    known = sources.get(key, set())
    # Two snapshots per managed file, and a rollback needs both: the pre-install
    # state it restores, and the post-install state it uses to tell its own
    # output from a concurrent edit. They live under distinct names - the
    # post-install one carries the ".installed" suffix - so a restore that asks
    # for one while naming the other reads as present while restoring the wrong
    # content. Check each against the class it must belong to.
    if before.endswith(".installed"):
        problems.append(
            f"{key}: pre-install snapshot {before!r} uses the post-install name")
    elif before not in known:
        problems.append(
            f"{key}: restore wants {before!r}, but backup_file writes "
            f"{sorted(known) or 'nothing'}")
    if installed not in known:
        problems.append(
            f"{key}: restore wants {installed!r}, but backup_file writes "
            f"{sorted(known) or 'nothing'}")

if problems:
    for problem in problems:
        print(f"FAIL {problem}", file=sys.stderr)
    sys.exit(1)
print("installer snapshot pairs: ok")
PY
