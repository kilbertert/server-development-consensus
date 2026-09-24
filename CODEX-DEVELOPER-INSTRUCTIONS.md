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

Commit messages must use Conventional Commits (`<type>(<scope>): <subject>`);
the managed `commit-msg` hook enforces this at commit time. Keep each commit
small and focused (normally under ~300 changed lines; a PR under ~500-800
lines), and use a lightweight PR template (`changes`/`tests`/`checklist`) when
one is provided. When a repository publishes versions, tag the merged default
branch with an annotated Semantic Version tag (`MAJOR.MINOR.PATCH`). A
repository whose work reaches a consumer outside the development host — a
published artifact or a deployed service — also keeps a Keep a Changelog
`CHANGELOG.md`, declared with `serverPolicy.publishesVersions=true` rather than
inferred; `dev-changelog` renders it, and the policy audit reports a missing or
drifted one.

The repository root is a delivery surface. Before editing and before handoff,
report its path, current branch, `git status --short --branch`, `git worktree
list`, and `git branch -vv`. A task worktree is not the canonical checkout
unless its handoff path is explicitly recorded. Create isolated tasks with
`dev-worktree start TYPE DESCRIPTION [PATH]`; it records the current origin base
and does not track the default branch. Task worktrees live in the managed
central area `~/Projects/.worktrees/` by default; an explicit path is honored
only inside a repository checkout, and visible top-level paths are rejected.
The Projects top level holds only canonical checkouts named after their origin
repository, installer-maintained policy and index files, and
underscore-prefixed functional directories (`_archive/`, `_runners/`). Idle
projects archive to `_archive/<year>/` and move back to the top level before
work resumes; deployment artifacts such as runner directories live under
`_runners/`. Run `dev-worktree audit` before handoff
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
delegation** for local development; **Devin Review** for automatic GitHub PR
review; and **CI/Ruleset** as the only mandatory quality
gate. At a meaningful implementation milestone, run local `ocr review` against
the workspace, commit, or task branch only with an approved local provider;
otherwise invoke OpenCodeReview's delegation mode as a bounded second opinion.
Do not run it after every edit, agent turn, or push. Always run `--preview`
first and read the selected-file count: OCR filters by extension and path rules,
so a change it filters out is reported as a clean run rather than as an
unreviewed one. Preview and review the same change set — the workspace form
while the milestone is uncommitted, the branch range once it is committed.
Record the layer as not applicable when it selects nothing (a
documentation-only change, for example), and state the count when it covers only
part of the change. Triage its findings once: fix verified defects, explicitly
record false positives or accepted risks, and do not turn speculative model
suggestions into an open-ended repair loop.
Devin Review automatically reviews a PR when it is opened, reopened, or marked
ready for review. It does not rerun after every push. The responsible agent
waits for the result, triages it once, fixes verified defects, and records false
positives or accepted risks. When auto-fix is enabled it may push a fix commit
to the task branch: commit your own work first, then fetch and rebase on the
remote task branch; never force-push it, and never discard uncommitted
work to make a rebase run. After a material change, the agent requests
one re-review with `/devin review`; never require the human operator to trigger
the normal review loop manually. Posting that request is also what unblocks the
branch: the Ruleset requires conversation resolution, and Devin resolves the
threads it considers addressed only at re-review. Fixing findings without
requesting the re-review leaves your own merge blocked. A finding triaged as not
applicable is answered in the thread and resolved by a human, with the reasoning
recorded — that is triage, and it is the only sanctioned way past the gate.
Devin Review's own status check stays **non-required**, which is what keeps the
vendor out of the merge path, and any user with write access can resolve a
thread, so the reviewer cannot hold a branch hostage.
A self-hosted ClawSweeper-like service, if adopted, is a separate PR/issue
evidence reviewer with its own least-privilege GitHub App and queue; installing
the public App alone is insufficient. It may receive only an explicitly allowed
PR/repository context, never TEAM-MEMORY, host configuration, logs, or
credentials; public comments need human approval after redaction. Neither
Devin Review nor OCR may be a required merge check. The OpenCodeReview
GitHub Action is retired and must not be re-enabled.
The self-hosted `review-sentinel/` service remains disabled until it has a
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
