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
gate. AI review is advisory by default, runs only when the PR is ready or a
human requests it, and must not rerun on every push. Fix verified findings;
explicitly triage false positives, out-of-scope findings, and accepted risks.
CodeRabbit is the preferred opt-in reviewer and owns the review-ready label.
OpenCodeReview is a manual fallback only, never a required check, and reviews
each PR head SHA at most once unless a human explicitly forces a repeat.

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
