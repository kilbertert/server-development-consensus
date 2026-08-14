The server development workflow is non-negotiable across every repository.
Treat its policy, Codex instructions, common library, commands, managed hooks,
audit units, and configuration as one release unit. Deploy only through the
canonical installer; after a rollback, fix the blocker and rerun it instead of
manually projecting an individual policy or tool file.
For any task that will edit maintained files, inspect Git status, the current
branch, the remote default branch, and existing user changes before editing.
If on the default branch, create one short-lived task branch first; preserve
existing uncommitted work on that branch and never discard it to clean the
worktree. Read-only investigation does not require a branch.

Normal delivery is: establish the canonical checkout and inspect all worktrees
-> one logical task -> one short-lived branch/worktree based on the latest
origin default branch -> focused commits and relevant formatter/static
checks/tests/build -> one pull request -> all required deterministic CI passes
-> human review -> merge through GitHub -> verify the merge and changed paths
on origin/default -> fast-forward local default -> delete only agent-owned task
branches and worktrees. Multiple commits and pushes belong to the same PR.
Never push or force-push directly to the default branch, use --no-verify, or
disable hooks, Rulesets, tests, or required deterministic checks to bypass the
gate.

The repository root is a delivery surface. Before editing and before handoff,
report its path, current branch, `git status --short --branch`, `git worktree
list`, and `git branch -vv`. A task worktree is not the canonical checkout
unless its handoff path is explicitly recorded. Create isolated tasks with
`dev-worktree start TYPE DESCRIPTION PATH`; it records the current origin base
and does not track the default branch. Run `dev-worktree audit` before handoff
and `dev-worktree retire PATH` only after integration is verified. Use
`dev-worktree preserve PATH REASON` for intentionally paused user work; this
does not bypass the pre-push overlap guard. The guard rejects a push whose
committed paths overlap uncommitted paths in another worktree, and the daily
audit reports stale lifecycle states without deleting them.

An upstream marked `[gone]` is a stale-delivery state, not an integrated
project. Before opening or merging a PR, fetch with pruning and verify the task
branch contains the current base; update it and rerun deterministic CI when the
base moved. After merge, confirm `gh pr view` is `MERGED`, capture the hosting
merge commit, verify maintained paths with `git show origin/<default>:<path>`,
and report remote branch deletion, local branch deletion, and worktree cleanup
separately. Preserve user-owned worktrees and uncommitted changes. If `gh pr
merge` selects a local merge path because another worktree has the default
branch checked out, use the hosting merge API or UI after the gates pass instead
of moving or resetting that worktree.

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

Engineering articles use one explicit public-projection workflow. You may
recommend an article at a meaningful milestone, but do not write, push, merge,
or deploy public blog content unless the current task authorizes publication.
Create a human-readable publication brief from verified outcomes, rewrite the
article as a separate artifact, remove private operational context, and state
the exact acceptance scope and unproven boundaries. Use an isolated branch or
worktree of the canonical blog repository, run its article/content/build/site
checks, open one focused PR, wait for deterministic CI, merge through GitHub,
and deploy only from a clean canonical blog main checkout. Report
`merged_waiting_deploy` when root access, a clean canonical checkout, or a
production gate is unavailable. Never move another task's uncommitted work or
claim that a merged article is live without public URL verification.
