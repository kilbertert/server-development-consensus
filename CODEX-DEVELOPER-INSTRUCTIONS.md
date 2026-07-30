The server development workflow is non-negotiable across every repository.
For any task that will edit maintained files, inspect Git status, the current
branch, the remote default branch, and existing user changes before editing.
If on the default branch, create one short-lived task branch first; preserve
existing uncommitted work on that branch and never discard it to clean the
worktree. Read-only investigation does not require a branch.

Normal delivery is: one logical task -> one short-lived branch -> focused
commits and relevant formatter/static checks/tests/build -> one pull request ->
all required deterministic CI passes -> human review -> merge through GitHub ->
delete the task branch. Multiple commits and pushes belong to the same PR.
Never push or force-push directly to the default branch, use --no-verify, or
disable hooks, Rulesets, tests, or required deterministic checks to bypass the
gate.

The server's three review layers are fixed: **OpenCodeReview CLI +
delegation** for local development; **ClawSweeper/CodeRabbit** for external or
queue-based GitHub PR review; and **CI/Ruleset** as the only mandatory quality
gate. At a meaningful implementation milestone, run local `ocr review` against
the workspace, commit, or task branch only with an approved local provider;
otherwise invoke OpenCodeReview's delegation mode as a bounded second opinion.
Do not run it after every edit, agent turn, or push. Triage its findings once:
fix verified defects, explicitly record false positives or accepted risks, and
do not turn speculative model suggestions into an open-ended repair loop.
CodeRabbit is an optional managed PR reviewer and owns the `review-ready` label.
A self-hosted ClawSweeper-like service, if adopted, is a separate PR/issue
evidence reviewer with its own least-privilege GitHub App and queue; installing
the public App alone is insufficient. It may receive only an explicitly allowed
PR/repository context, never TEAM-MEMORY, host configuration, logs, or
credentials; public comments need human approval after redaction. Neither
managed AI review nor OCR may be a required merge check. The OpenCodeReview
GitHub Action is retired and must not be re-enabled.
The self-hosted `ops/review-sentinel/` service remains disabled until it has a
dedicated Codex executable/home and separately managed App credentials; never
point it at the interactive `~/.codex` home.

Creating a local task branch is normal preparation. Commit, push, PR, merge,
release, and deployment actions still require authorization from the current
task. Urgent work uses hotfix/* and the same PR/review flow. Break-glass action
requires explicit current-task human approval, a recorded incident reason,
immediate restoration of guards, and a retrospective PR; agents cannot
self-authorize it.

TEAM-MEMORY and all other internal engineering records are private by default.
Never directly or bulk-sync raw memory, logs, commit streams, repository
metadata, filesystem paths, service topology, account data, or credentials to
a public service. Public material must be a separate artifact that is
explicitly selected, redacted, edited, and human-approved. Public projections
are not authoritative and cannot overwrite or approve internal sources. Public
feedback may create an inbox candidate only; it must never automatically modify
or approve formal TEAM-MEMORY. When sensitivity is unclear, keep the material
private.
