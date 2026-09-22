# Devin Review Migration Plan

Implements `docs/adr/0003-devin-review-as-sole-first-pass-reviewer.md`. Phases
run in order; Phase 0 and Phase 2 are blockers for Phase 4.

Measured starting state (2026-09-21):

| Fact | Value |
| --- | --- |
| Repositories | 54 public, 16 private |
| Repositories with Rulesets | 0 |
| PR-Agent | `disabled` + `inactive`; port 8766 released; 30-day success count 0 |
| CodeRabbit | active on enrolled repositories; 11 `.coderabbit.yaml` files |
| Devin Review | enrolled on 4 repositories; first review `kilbertert/AI-Ops#345` |
| Reviewer count in the first-pass slot | 2 live (CodeRabbit, Devin), 1 dead (PR-Agent) |

## Phase 0 — Per-repository publication preconditions (blocking)

Publication is gated per repository. A repository that fails this phase stays
private and is not enrolled; it is not a reason to weaken the phase.

1. **Third-party personal data removed from the tree and from history.**
   Publishing a history that still contains the file publishes the file.
   - `shanghai_dialect_dataset` — voice dataset (speaker recordings).
   - `genesis-health` — `中英文双语完整版个人体检报告.pdf`, plus third-party
     product material (`郅臻堂*`, `铠迩康*`).
   - `sports-ability` — student physical-test and face-recognition data.
   - `AI-Ops` — a client's production topology: real production IPs, an Aliyun
     RDS endpoint, client domains, database, table, Redis stream and ACL names,
     and tenant identifiers, at HEAD and throughout history. This repository is
     public today, so this is a live disclosure whose history cannot be
     recalled: assess it as a recorded exposure with the client rather than as a
     pre-publication cleanup.
   - Action: drop from the working tree, purge from history
     (`git filter-repo` or BFG), force-push the rewritten history, and keep the
     data in private storage outside the repository. A repository where the
     data cannot be separated is not published.
2. **Credential scan and rotation, in that order.** Rotate first, purge second,
   publish third: publishing first exposes a working secret even if it is
   removed minutes later.
   - `gitleaks` and `trufflehog` are not installed on the development host; one
     of them is required for this phase.
   - Known pattern hits to start from: `sports-ability` (1), `genesis-health` (2).
   - After publication, GitHub secret scanning and push protection are free for
     public repositories and become the standing control.
3. **Fork status confirmed.** `sports-ability` is a fork whose parent is not
   visible to the account; fork visibility changes do not behave like ordinary
   repository visibility changes.

## Phase 1 — Devin Review configuration (Devin webapp)

1. **Enrolled repositories by observed PR traffic, not by inventory.** Traffic
   in the retired reviewer's logs: `AI-Ops` (44), `sports-ability` (28),
   `server-development-consensus` (20), `newenergy-ai-article-platform` (20),
   `ds408-visualizer` (6), `genesis-evidence` (2). The enrolled set is `AI-Ops`,
   `Auto_Test`, `server-development-consensus` and `genesis-evidence`.
   `sports-ability` is deliberately not enrolled: it stays private, so the
   open-source tier does not apply, and enrolling it would send minors' sports
   and genetic data, a live relay credential and client identifiers to a third
   party. It keeps CodeRabbit until it clears Phase 0 or is reviewed manually.
   `newenergy-ai-article-platform` and `ds408-visualizer` are added when their
   next pull request arrives.
2. **Trigger mode** stays `When the PR is ready` (reviews on open or
   draft-to-ready; does not re-run per push).
3. **`Per-PR on-demand spend limit`** — currently `No limit`; set a cap.
4. **Personal review trigger** (`Settings > Preferences`) reviewed: an enrolled
   user widens scope to any PR that user authors on any repository, which is a
   larger cost surface than the repository list.
5. **`REVIEW.md` per enrolled repository.** Note that Devin also reads
   `AGENTS.md`, so each repository's existing governance text is fed to the
   reviewer; confirm that is intended before adding review-specific rules.
6. **Auto-fix** is enabled by operator decision, configured as
   `Settings > Customization > Pull requests > Responding to bots` →
   `Selected only` → `devin-ai-integration[bot]`, never `All bots`. Because it
   may push a commit to a task branch, the responsible agent rebases on the
   remote task branch before continuing and never force-pushes it.
7. **Verify.** Open a pull request that changes one line of a README, confirm a
   `devin-ai-integration[bot]` review appears, and confirm no other reviewer
   comments.

## Phase 2 — Stand down the existing reviewers

1. **PR-Agent** — done: `systemctl --user disable --now pr-agent.service`
   (unit, virtualenv and `~/.config/pr-agent/` retained for rollback). No
   automation depended on it: the installer `bin/`, `lib/` and `policy/`
   directories, the port registry, and the policy audit contain no reference to
   the unit or port 8766.
2. **CodeRabbit** — the announced sole reviewer cannot coexist with it on the
   enrolled repositories. Stand it down there by dropping those repositories
   from the GitHub App installation, which is reversible in one act, and leave
   every `.coderabbit.yaml` file in place for rollback. Disabling the governance
   repository's own file in this change is the exception, because it is the
   repository whose test asserts the old arrangement. The remaining
   repositories keep CodeRabbit until they are enrolled, which the installation
   selection reflects rather than a checkpoint. This flipped the governance
   repository's assertion in `tests/test-ai-review-policy.py` to
   `test_retired_coderabbit_config_is_preserved_but_disabled`, which now
   requires `auto_review: enabled: false` while `drafts`,
   `auto_incremental_review` and `labels: ["review-ready"]` stay as they were.
3. **`review-sentinel`** — unchanged. It is disabled, and its files and tests
   stay in place; deleting them is a separate decision.
4. **`ocr review`** — retained as the local, pre-PR development tool. It is not
   a PR-level reviewer and does not occupy the slot this migration targets.

## Phase 3 — Governance change (task branch to pull request)

The migration is one governance change delivered in one pull request:
[pull request
#31](https://github.com/kilbertert/server-development-consensus/pull/31) as
squash commit `ee1062b`. Two follow-ups carried what it should have included —
the QA record for the first two cases and the `VERSION` bump `1.8.0` that #31
omitted, in [pull request
#32](https://github.com/kilbertert/server-development-consensus/pull/32), and the
correction to the table below in pull request #33. The split is recorded rather
than tidied away, because it is a defect in how the change was delivered and not
the shape the phase asks for.

One change, one pull request, deterministic CI. `test-ai-review-policy.py` is
fail-closed: changing the documentation without changing the assertions fails CI,
and vice versa.

| File | Change |
| --- | --- |
| `SERVER-DEVELOPMENT-CONSENSUS.md` | three-layer architecture with `Devin Review` in the automatic layer; review budgets; `/devin review` and the auto-fix rebase rule; Development Review Sequence steps 7 and 8 |
| `README.md` | three review-layer statements including `Devin Review remains advisory` |
| `CODEX-DEVELOPER-INSTRUCTIONS.md` | three review-layer statements including `Neither Devin Review nor OCR may be a required merge check` |
| `tests/test-ai-review-policy.py` | 8 rewritten assertions in `test_review_roles_and_budget_are_explicit_across_governance_files`, the fail-closed `PR-Agent` absence assertions, and `test_retired_coderabbit_config_is_preserved_but_disabled` |
| `.coderabbit.yaml` | the governance repository's own file flipped to `auto_review: enabled: false` |
| `docs/adr/0003-*` | this decision (promote `proposed` to `accepted` on merge) |
| `acceptance.feature` | observable scenarios: a PR to an enrolled repository receives exactly one Devin Review; no second reviewer posts; findings remain advisory and never a required check |
| `qa-plan.md` | executable case with ID, environment, preconditions, ordered actions, observable results and cleanup |

Invariants that must survive the rewrite: AI review is advisory and never a
required check; one automated review per milestone plus at most one re-review;
reviewer output is a candidate until a human confirms it.

## Phase 4 — Publication and Rulesets

Status `2026-09-21`: every repository below is already public, so no visibility
flip remains for them, and `protected default branch` is active on all six that
the phase then covered. `Health-Flow` was added to the table on `2026-09-22`
after being found by enumerating public repositories, and carries the Ruleset
`23809254`; the count in this paragraph is left as the state the phase closed in
rather than restated, so that the omission stays visible.
It was created on `kilbertert/server-development-consensus` first and validated on
pull request #34 before the other five followed: that pull request reports
`isRequired: true` for `Governance release unit` and `isRequired: false` for
`Devin Review`, and merged with the rules in force. The two limitations recorded
when this phase closed — the `AI-Ops` fork gate and the duplicate `Auto_Test`
Ruleset — were both closed later the same day; neither was an accepted risk.

1. Flip visibility per repository, ordered by Phase 0 completion, one at a time.
   Met for every repository in the table below except `sports-ability`, which is
   the only one with a flip still ahead of it.
2. Enable a Ruleset on each published repository: pull request required, branch
   current before merge, no bypass actors, existing deterministic checks
   required. This is free for public repositories.

   The applied Ruleset is `protected default branch` on `~DEFAULT_BRANCH` with
   `bypass_actors: []` and four rules: `deletion`, `non_fast_forward`,
   `pull_request` with `required_approving_review_count: 0` and
   `required_review_thread_resolution: true`, and `required_status_checks` with
   `strict_required_status_checks_policy: true`.

   The reviewer's own status check stays off, and must: it is a `StatusContext`
   that is pending for the life of the pull request, so requiring it would bind
   merge availability to a third-party vendor's uptime. This plan originally
   listed `required_review_thread_resolution` alongside it as a second parameter
   that "promotes advisory AI output into a required merge gate". That reasoning
   was too broad, and the measurement showed why. A month of pull requests
   recorded the outcome of the two parameters being off together: 23 of 24
   finding-bearing pull requests across four repositories were merged with their
   threads unresolved, and every merge happened within 268 seconds of the review
   (`Health-Flow#104`: 84 seconds, head unchanged, three findings, zero replies).
   The rule "a human must confirm severity" was enforced by nothing.

   Conversation resolution is not the reviewer's check under another name. It
   gates a *state* — every thread answered — rather than a *service*. An absent
   reviewer opens no thread and costs no merge availability; any user with write
   access can resolve a thread, so the reviewer cannot hold a branch hostage;
   and Devin resolves only the threads it considers addressed, at re-review, so
   the gate is satisfied by doing the work rather than by waiting. The two
   parameters differ in exactly the way that matters: one makes a vendor's
   availability a merge precondition, the other makes an unanswered question one.

   A required check is a job of a workflow that triggers on `pull_request` for
   that repository, and nothing else. `agent-*.yml` runs on
   `pull_request_target` and `architecture-review.yml` runs on a schedule, so
   neither produces a check on a pull request head, and requiring one blocks
   merges permanently. Names are matched exactly, including case.

   | Repository | Required checks |
   | --- | --- |
   | `server-development-consensus` | `Governance release unit` |
   | `AI-Ops` | `Workflow policy`, `verify`, `windows-verify` |
   | `Auto_Test` | `Workflow policy`, `Verify`, `Windows Verify` |
   | `genesis-evidence` | `Workflow policy`, `quality` |
   | `newenergy-ai-article-platform` | `build` |
   | `ds408-visualizer` | `smoke` |
   | `Health-Flow` | `Workflow policy` |

   `Health-Flow` is listed seventh because it was **missing from this table**, and
   that omission is what let it go without a Ruleset at all: it is public, so the
   phase applied to it, but a table that does not name a repository cannot be
   checked against reality. It was found by enumerating public repositories and
   asking which of them carried a Ruleset, not by reading this list. Its required
   check was taken from the one workflow that actually triggers on
   `pull_request` there (`AFK Policy` → job `Workflow policy`), verified before
   being required, because requiring a check that never fires blocks every merge
   permanently. Ruleset `23809254`, created with the triage gate included.

   `windows-verify` on `AI-Ops` is the check to watch: strict mode lets a slow or
   flaky check stall every merge, so it leaves that list if the first pull
   requests show it.

   One required check is weaker than it reads. On `AI-Ops`, `verify` ran on the
   repository's self-hosted runner, so the workflow guarded it to skip fork pull
   requests, and GitHub counts a skipped required job as a success: a fork pull
   request satisfied the Ruleset without the Linux checks ever running. The guard
   was a security boundary the workflow states in its own comment, not an
   oversight, and closing it meant either moving the job back to a GitHub-hosted
   runner or failing fork pull requests closed from a separate required job. The
   first remedy was taken: pull request #351 moved `verify` to `ubuntu-latest`
   and deleted the fork gate, merging as `48773b7`, and the required check list
   above is unchanged. The three workflows that stay on the self-hosted runner —
   `agent-*.yml` and `architecture-review.yml` — produce no pull-request check,
   so the fork path no longer reaches a required gate.

   `Auto_Test` also carried an older `Require pull requests` Ruleset (`19944653`)
   whose single rule the new one subsumes. Two Rulesets naming the same condition
   is how two records drift apart, so it was deleted; `protected default branch`
   (`23760872`) is now the repository's only Ruleset.
3. Verify with `gh api repos/kilbertert/<repo>/rulesets` and
   `gh api repos/kilbertert/<repo>/rules/branches/<default>`.

## Phase 5 — Acceptance

On a real pull request against an enrolled repository, record: exactly one
Devin Review on the ready head, no CodeRabbit or PR-Agent comment, CI green,
Ruleset satisfied. Record commit or build identity, environment, timestamp and
the retained artifact.

## Open decisions

- Whether Devin Review's open-source free tier covers a repository that was
  private and became public; verify against the Usage page rather than assuming.
- Which of the 16 private repositories publish, per Phase 0 outcome.
- When the retired reviewers are deleted rather than left disabled.
- **Decided on `2026-09-21`:** the canary comparison is dropped. The operator
  settled the question by reading both reviewers' output directly and judging
  Devin Review's reports better, so no counted comparison is required before the
  remaining repositories follow. The remaining repositories keep CodeRabbit
  until they are enrolled, and the revert tripwire stays in force on its own: if
  reports degrade into an explanatory misreport storm, the layer is reverted
  regardless of any count.
