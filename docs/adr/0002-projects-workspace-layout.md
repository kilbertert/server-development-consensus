---
status: accepted
---

# Projects Workspace Layout

The `/home/claude/Projects` top level had accumulated task worktrees, runner
directories, backups, and loose documents next to canonical project checkouts.
A cleanup on 2026-09-12 retired 11 ad-hoc task worktrees, archived idle
projects and backups into `_archive/2026/`, and moved four self-hosted runner
directories into `_runners/`, but nothing prevented the clutter from
re-accumulating.

## Decision

The policy defines a curated top level: canonical checkouts named after their
origin repository, installer-maintained policy and index files, and
underscore-prefixed functional directories (`_archive/`, `_runners/`).
`dev-worktree start TYPE DESCRIPTION [PATH]` creates task worktrees in the
managed central area `~/Projects/.worktrees/` by default; an explicit path is
honored only inside a repository checkout, and visible top-level paths are
rejected by the tool. `dev-worktree audit` and the daily policy audit report
legacy top-level worktrees as violations without failing during the migration
window. Projects follow restore-then-work archiving into `_archive/<year>/`,
and deployment artifacts (runner directories, deploy/standby checkouts) live
under `_runners/` or a service-managed location.

## Consequences

New clutter is blocked at the tool boundary for every agent that uses
`dev-worktree`, and the daily audit makes any remaining top-level worktree
visible until the service migration relocates it. Self-hosted runners keep
absolute `bin`/`externals` symlinks after version updates, so any runner
directory move requires re-pointing them (relatively) before restart. The cost
is one more policy section, an optional path argument, and one audit rule.

## Rejected alternatives

- Per-repository `.worktrees/` directories as the only sanctioned location:
  they need per-repository ignore setup and bury task state inside project
  trees; the central area keeps the top level flat and auditable.
- Failing the daily audit on legacy top-level worktrees immediately: it would
  block active agent sessions and the installer before the runner/service
  migration completes.
- Relying on convention without a tool change: the same clutter re-appeared
  within hours during the cleanup itself.
