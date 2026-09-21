# Server development consensus deployment

The shared vocabulary for server governance and AFK execution lives in
[`CONTEXT.md`](CONTEXT.md); the accepted layered-boundary decision is
[`docs/adr/0001-layered-afk-governance.md`](docs/adr/0001-layered-afk-governance.md).

This repository is the canonical source of the server development governance
release unit: the consensus policy, the installer, the managed commands, the
audit units, and the review-sentinel reference implementation. Deploy it only
through `install.sh` from a clean checkout of this repository's default branch.

It was extracted on 2026-08-18 from
`kilibtert/helixent-agent-workbench` (local path `~/Projects/praxis`), which is
the Helixent product repository and no longer hosts server-level governance.
Git history is preserved: the consensus unit arrived via `git subtree split`
of `ops/server-development-consensus`, and `review-sentinel/` retains its three
commits as merge ancestry of the import commit.

`SERVER-DEVELOPMENT-CONSENSUS.md` is the canonical human and agent policy. All
development must live below `/home/claude/Projects`, whose inherited copies are:

- `~/Projects/AGENTS.md`
- `~/Projects/CLAUDE.md`
- `~/Projects/SERVER-DEVELOPMENT-CONSENSUS.md`

`DEVELOPMENT-PORT-REGISTRY.md` is the separate source of truth for fixed
development host-port allocations. The installer publishes it to:

- `~/.config/server-development-consensus/DEVELOPMENT-PORT-REGISTRY.md`
- `~/Projects/DEVELOPMENT-PORT-REGISTRY.md`

The installer updates user-global Codex and Claude files when they are missing
or user-writable. Root-maintained immutable files are preserved. Codex also
receives the core Git workflow through a TOML-validated update of the
user-writable `developer_instructions` field in `~/.codex/config.toml`, while
all unrelated model, provider, project, MCP, hook, and plugin settings remain
unchanged. The managed Codex defaults are an 872000-token context window and a
700000-token automatic-compaction threshold. Operators should verify the
selected model catalog advertises that window before installation. The updater
uses `tomlkit`, an explicit installer prerequisite, to preserve unrelated TOML
and comments safely.

The policy, Codex instructions, common library, commands, managed hooks, audit
units, and configuration are one release unit. Deploy them only through
`install.sh`. If installation rolls back, resolve the blocker and rerun the
installer; do not manually copy an individual policy or tool file into place.

The policy also defines an internal-knowledge/public-projection boundary.
TEAM-MEMORY and other engineering records remain private by default; public
material must be a separate, selected, redacted, edited, human-approved
artifact and cannot mutate or approve its internal source.

The Engineering Article Release contract standardizes a frequent cross-project
workflow without making publication automatic. After explicit authorization,
an agent creates a verified and redacted publication brief, writes a separate
article in an isolated `ranlei-blog` task worktree, runs content and rendering
checks, uses one PR and deterministic CI, and deploys only from the clean
canonical blog `main`. Its terminal states distinguish `merged_waiting_deploy`
from `live`, so a Git merge or local Hugo build cannot be reported as a
production publication.

The acceptance and system-test contract covers user-visible and cross-system
changes from requirement through evidence. It uses Gherkin scenarios for
observable acceptance outcomes, an executable QA plan for system verification,
and traceable result artifacts. Complexity/coverage and mutation analysis are
risk-triggered rather than universal gates; agents may fill specification,
implementation, review, hardening, or QA roles, but the maintained artifacts
and deterministic results are the contract.

The local enforcement layer is installed at:

- `~/.config/git/hooks/pre-push`
- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/commit-msg`
- forwarding wrappers for every other Git hook name
- `~/.local/lib/server-development-consensus/dev-git-common.sh`
- `~/.local/bin/dev-start`
- `~/.local/bin/dev-pr`
- `~/.local/bin/dev-worktree`
- `~/.local/bin/dev-policy-audit`
- `~/.local/bin/sync-privileged-policy`
- `~/.config/systemd/user/dev-policy-audit.{service,timer}`

GitHub Rulesets are the authoritative remote control for supported public
repositories. The local hook provides fast feedback and covers private
repositories that GitHub Free cannot protect remotely. Local hooks can be
bypassed with low-level Git options, so they complement rather than replace
remote Rulesets. Policy prohibits bypassing either layer.

Every repository in the workspace has a repository class. A server-managed
repository — the default — owns its delivery process here, so the full policy
applies. An externally governed repository belongs to another organization's
review, merge, and release process: it keeps its own commit convention,
hooks, and workflow, and the managed hooks forward to them instead of
enforcing the server delivery contract. The class is a local marker on the
checkout, never committed and never part of the repository; the host owner
records the classification and its owning organization in the private
operations inventory. The account boundary, secret isolation, workspace
layout, worktree location, port registry, and host rules apply to every
repository regardless of class, and an unknown class is treated as
server-managed.

The managed `commit-msg` hook enforces Conventional Commits
(`<type>(<scope>): <subject>`, types `feat fix docs style refactor perf test
chore build ci revert`, optional `!` for breaking changes and an optional
scope) at commit time. It is fail-closed: a repository that opts out must set
`serverPolicy.commitMessageOverride=default-branch-only` explicitly (which
keeps the check on the default branch and allows legacy messages on task
branches during migration).

AI review is deliberately separate from the deterministic merge gate. The
server's three-layer architecture is explicit: **OpenCodeReview CLI +
delegation** for local development; **Devin Review** for automatic GitHub PR
review; and **CI/Ruleset** as the only mandatory quality
gate. The default development-time review uses local OpenCodeReview: `ocr review`
inspects a workspace, commit, or branch range as the `claude` user when an
approved local provider is configured, while the agent integrations use
delegation mode when one is not. It is useful as a focused second opinion after
a coherent implementation milestone, but must not run after every edit, agent
turn, or push. It does not use a GitHub Action and does not depend on an OCR
gateway.

Devin Review automatically reviews the initial ready PR when it is opened,
reopened, or marked ready for review. It does not rerun after every push. The
responsible agent waits for the review, triages findings once, fixes verified
defects, and records false positives or accepted risks. Auto-fix may push a fix
commit to the task branch, so the agent commits its own work first, then fetches
and rebases on the remote task branch; it never force-pushes, and
never discards uncommitted work to make a rebase run. After a material change,
the agent requests one re-review with `/devin review`; the human operator does
not manually drive the normal review loop. Devin Review remains advisory, while
CI and Rulesets remain the only mandatory merge gates. CodeRabbit is the
rollback path for this layer: it is stood down through its GitHub App
installation rather than by deleting its configuration.

ClawSweeper is a different system: a self-hosted GitHub PR/issue review queue
that can publish one durable evidence and merge-readiness report. The
OpenClaw-hosted instance is not a public service for third-party repositories;
installing its GitHub App alone does not create a backend for this server. A
future server instance must begin as review-only, with read-only model workers,
least-privilege GitHub App tokens, exact-head deduplication, bounded queues and
budgets, and a human-triaged comment. It must not start with repair, push,
automerge, close, or state-publication capabilities.

Before any ClawSweeper-like deployment, the organization must explicitly allow
each repository and approve the model provider and retention boundary. Review
workers may receive only selected repository and PR context; they must never
read TEAM-MEMORY, host configuration, logs, or credentials. For a public
repository, the generated report is a redacted candidate that needs human
approval before a public GitHub comment is published.

The first review-only implementation is `review-sentinel/`. It provides a
GitHub App webhook, an SQLite exact-head queue, a read-only structured Codex
worker, and a marker-backed publisher. Its installer deliberately leaves the
user service disabled until an owner creates a separate private GitHub App and
fills the allowlist and secret files. It does not copy ClawSweeper's worker
fleet, Cloudflare state, repair, push, close, or automerge infrastructure.

The retired OpenCodeReview workflow is not part of this architecture and must
not be re-enabled. A local OCR pass, one automatic Devin Review, and at most one
agent-requested re-review after a material change are the default budget for one
logical milestone.

Repositories that configure a local `core.hooksPath` are migrated by storing
the old path in `serverPolicy.chainedHooksPath` and using the global wrappers.
The wrappers run the server guard and then the original project hook. A prior
global `core.hooksPath` is similarly preserved in
`serverPolicy.globalChainedHooksPath`; project-local hooks retain precedence,
matching Git's original configuration semantics.

Repositories that publish versions use Semantic Versioning (`MAJOR.MINOR.PATCH`)
and annotated tags on the merged default branch; releases are an explicit,
authorized act. PRs should stay focused (normally under ~500-800 lines) and
use a lightweight PR template (`changes`/`tests`/`checklist`) when provided.

For isolated task work, use `dev-worktree start TYPE DESCRIPTION [PATH]`. The
command fetches the remote default branch, creates a no-track task branch from
that exact commit, and records local lifecycle metadata. `dev-worktree audit`
reports every sibling worktree and fails on stale delivery states;
`dev-worktree preserve PATH REASON` records intentionally paused user work;
and `dev-worktree retire PATH` removes only a clean branch whose changes are
verified as integrated. The global pre-push hook independently rejects a push
when its committed paths overlap uncommitted paths in another worktree. None of
these commands automatically delete dirty work or a remote branch.

Run `dev-policy-audit` to inspect every repository or
`dev-policy-audit --repair` after adding repositories. The repair operation
records default branches, enables global hooks, and safely chains local hooks.
The enabled user timer audits drift once per day without automatically changing
repository state.

The installer is intentionally account-specific: run it as `claude` with
`HOME=/home/claude`. It backs up agent files, Codex config, Git config, global
hooks, and resolved config paths for ordinary repositories, linked worktrees,
and gitfile repositories before replacement. A user-level lock prevents
concurrent installs, and a failed install restores managed files, global Git
configuration, hooks, and project Git configs from that backup. If the user
systemd manager is unavailable, files are still installed and the timer is
reported as not enabled instead of leaving an ambiguous failure.

Root-maintained policy mirrors are intentionally outside the ordinary
installer's write boundary. After reviewing the canonical installed policy,
an administrator synchronizes them explicitly:

```bash
expected_sha256="$(sha256sum /home/claude/.config/server-development-consensus/SERVER-DEVELOPMENT-CONSENSUS.md | awk '{print $1}')"
sudo install -o root -g root -m 0755 \
  /home/claude/.local/bin/sync-privileged-policy \
  /usr/local/sbin/sync-privileged-policy
sudo /usr/local/sbin/sync-privileged-policy \
  --expected-sha256 "$expected_sha256"
sudo /usr/local/sbin/sync-privileged-policy --verify \
  --expected-sha256 "$expected_sha256"
```

The privileged tool refuses to run from a user-owned or writable executable,
pins the user-owned canonical source to the explicitly reviewed SHA-256, and
has four fixed targets. It rejects symlinks and unexpected ownership, preserves
each target's mode and ownership, creates a complete pre-change backup below
`/var/backups/server-development-consensus`, writes a JSON manifest and an
append-only JSONL audit record, uses atomic replacement, and rolls back all
targets if a replacement or post-write verification fails. The four mirrors
are `/etc/agent-governance/server-development-consensus.md`,
`~/.codex/AGENTS.md`, `~/.codex/AGENTS.override.md`, and
`~/.claude/CLAUDE.md` (with `~` meaning `/home/claude`).

Rollback requires an explicit policy change. Restore the backed-up global Git
configuration, remove the installed hook/tools, restore the prior global agent
instruction files, and restore each repository's chained `core.hooksPath`.
Remote Rulesets must be changed separately and must never be removed merely to
work around a failed deterministic check. AI review policy may be changed by an
explicit governance decision based on measured value, cost, latency, and false
positives.
