# Server development consensus deployment

`SERVER-DEVELOPMENT-CONSENSUS.md` is the canonical human and agent policy. All
development must live below `/home/claude/Projects`, whose inherited copies are:

- `~/Projects/AGENTS.md`
- `~/Projects/CLAUDE.md`
- `~/Projects/SERVER-DEVELOPMENT-CONSENSUS.md`

The installer updates user-global Codex and Claude files when they are missing
or user-writable. Root-maintained immutable files are preserved. Codex also
receives the core Git workflow through a TOML-validated update of the
user-writable `developer_instructions` field in `~/.codex/config.toml`, while
all unrelated model, provider, project, MCP, hook, and plugin settings remain
unchanged. The updater uses `tomlkit`, an explicit installer prerequisite, to
preserve unrelated TOML and comments safely.

The policy also defines an internal-knowledge/public-projection boundary.
TEAM-MEMORY and other engineering records remain private by default; public
material must be a separate, selected, redacted, edited, human-approved
artifact and cannot mutate or approve its internal source.

The local enforcement layer is installed at:

- `~/.config/git/hooks/pre-push`
- `~/.config/git/hooks/pre-commit`
- forwarding wrappers for every other Git hook name
- `~/.local/lib/server-development-consensus/dev-git-common.sh`
- `~/.local/bin/dev-start`
- `~/.local/bin/dev-pr`
- `~/.local/bin/dev-policy-audit`
- `~/.local/bin/sync-privileged-policy`
- `~/.config/systemd/user/dev-policy-audit.{service,timer}`

GitHub Rulesets are the authoritative remote control for supported public
repositories. The local hook provides fast feedback and covers private
repositories that GitHub Free cannot protect remotely. Local hooks can be
bypassed with low-level Git options, so they complement rather than replace
remote Rulesets. Policy prohibits bypassing either layer.

AI review is deliberately separate from the deterministic merge gate. The
server's default development-time review uses local OpenCodeReview: `ocr review`
inspects a workspace, commit, or branch range as the `claude` user when an
approved local provider is configured, while the agent integrations use
delegation mode when one is not. It is useful as a focused second opinion after
a coherent implementation milestone, but must not run after every edit, agent
turn, or push. OpenCodeReview's GitHub Action is optional manual transport, not
its primary role and never a required check.

CodeRabbit is an optional managed PR reviewer after its GitHub App is authorized
for selected repositories. Repository configuration uses `reviews.profile:
chill`, manual or `review-ready` opt-in, no draft reviews, and no automatic
incremental review on every push. `review-ready` starts CodeRabbit only.
CodeRabbit pricing and trial terms are external product terms, so the server
does not depend on it as a permanent gate.

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

The optional OpenCodeReview workflow records the reviewed PR head SHA in a
hidden comment and skips duplicate runs; only an explicit workflow dispatch
with `force=true` may repeat the same SHA. Its action is `continue-on-error`,
so model findings, malformed output, gateway throttling, and timeouts remain
advisory evidence rather than merge failures. A local OCR pass and at most one
managed PR review round are the default budget for one logical milestone;
further runs need a material change or explicit human request.

CodeRabbit authorization requires an owner to sign in through the browser and
install the GitHub App for selected repositories. The repository YAML can be
prepared in advance, but CLI access cannot approve that external authorization.

Repositories that configure a local `core.hooksPath` are migrated by storing
the old path in `serverPolicy.chainedHooksPath` and using the global wrappers.
The wrappers run the server guard and then the original project hook. A prior
global `core.hooksPath` is similarly preserved in
`serverPolicy.globalChainedHooksPath`; project-local hooks retain precedence,
matching Git's original configuration semantics.

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
