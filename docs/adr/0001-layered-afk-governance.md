---
status: accepted
---

# Layered Governance for AFK Execution

`server-development-consensus` is the single source of server-wide governance invariants. `afk-bootstrap` is a project-level execution adapter: it maps those invariants to Planner, label-driven Actions, Docker, repository checks, and pull-request orchestration without redefining or weakening the baseline.

## Decision

The precedence order is:

1. `server-development-consensus` baseline;
2. repository rules that are stricter than the baseline;
3. AFK adapter prompts and implementation details.

The four execution planes have separate responsibilities:

| Plane | Primary responsibility |
|---|---|
| Interactive session | Confirm terminology, requirements, acceptance, and QA scope under the baseline |
| Host runner | Prepare clean task branches, run delivery checks, push branches, and open pull requests |
| Docker agent | Implement and commit task-branch changes using a portable policy check and scoped credentials |
| GitHub | Run deterministic CI and Ruleset enforcement; authorize the default-branch merge |

The normal state machine is `idea/grill -> PRD -> native sub-issues -> ready-for-agent -> AFK implement -> draft PR -> deterministic CI and review -> human QA -> GitHub merge`. The issue and pull request are the durable task identity.

The portable policy check is owned by the AFK adapter and is constrained to container-observable invariants: commit-message shape, task-branch/default-branch separation, clean-worktree expectations, and secret-access boundaries. The host runner repeats delivery checks before push. GitHub Rulesets remain the final merge control. A direct container push to `main` must be rejected by the container check, host wrapper, and Ruleset, each fail-closed.

Provider settings and short-lived, least-privilege GitHub tokens may be mounted read-only for the current task. Long-lived write credentials, `AGENT_PAT`, runner-registration tokens, label mutation, branch push, and pull-request creation remain on the host or GitHub workflow boundary.

The consensus release has a SemVer version. AFK has its own SemVer template version. Generated `.afk-bootstrap.json` records both plus a `consensus_compatibility` range; CI blocks missing or incompatible declarations. Repository owners upgrade AFK, while the consensus maintainer publishes the baseline and compatibility window.

Implementation differences such as Docker isolation, Playwright dependencies, or self-hosted workspace persistence use structured, owner-approved exceptions with a reason, scope, compensating control, approval timestamp, and expiry. Exceptions cannot relax account boundaries, secret isolation, default-branch protection, pull-request requirements, or deterministic merge gates.

## Consequences

Common Git and security semantics have one normative owner, while AFK can evolve its workflow mechanics without becoming a competing governance system. Every automated execution path needs an explicit host/GitHub enforcement point because server-global hooks are not inherited by Docker or hosted runners. Version incompatibility becomes a visible delivery blocker, and bounded exceptions remain auditable.

## Rejected alternatives

- Installing the complete server consensus release inside every AFK image duplicates account-specific configuration and creates a second installation lifecycle.
- Letting AFK or a chat session override the baseline makes security and protected-branch behavior depend on whichever prompt or template ran last.
- Giving containers long-lived write credentials would collapse the execution and delivery boundaries.
