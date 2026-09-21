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
   repositories keep CodeRabbit until the checkpoint below is met. This changes
   `tests/test-ai-review-policy.py::test_legacy_coderabbit_config_remains_non_incremental`,
   which currently asserts the files exist with `auto_review: enabled`,
   `drafts: "false"`, `auto_incremental_review: "false"` and
   `labels: ["review-ready"]`.
3. **`review-sentinel`** — unchanged. It is disabled, and its files and tests
   stay in place; deleting them is a separate decision.
4. **`ocr review`** — retained as the local, pre-PR development tool. It is not
   a PR-level reviewer and does not occupy the slot this migration targets.

## Phase 3 — Governance change (task branch to pull request)

One change, one pull request, deterministic CI. `test-ai-review-policy.py` is
fail-closed: changing the documentation without changing the assertions fails CI,
and vice versa.

| File | Change |
| --- | --- |
| `SERVER-DEVELOPMENT-CONSENSUS.md` | three-layer architecture (PR-Agent layer); review budgets; Development Review Sequence steps 7 and 8 |
| `README.md` | three PR-Agent statements including `Neither PR-Agent nor OCR may be a required merge check` |
| `CODEX-DEVELOPER-INSTRUCTIONS.md` | three PR-Agent statements |
| `tests/test-ai-review-policy.py` | 8 assertions in `test_review_roles_and_budget_are_explicit_across_governance_files`, plus `test_legacy_coderabbit_config_remains_non_incremental` |
| `docs/adr/0003-*` | this decision (promote `proposed` to `accepted` on merge) |
| `acceptance.feature` | observable scenarios: a PR to an enrolled repository receives exactly one Devin Review; no second reviewer posts; findings remain advisory and never a required check |
| `qa-plan.md` | executable case with ID, environment, preconditions, ordered actions, observable results and cleanup |

Invariants that must survive the rewrite: AI review is advisory and never a
required check; one automated review per milestone plus at most one re-review;
reviewer output is a candidate until a human confirms it.

## Phase 4 — Publication and Rulesets

1. Flip visibility per repository, ordered by Phase 0 completion, one at a time.
2. Enable a Ruleset on each published repository: pull request required, branch
   current before merge, no bypass actors, existing deterministic checks
   required. This is free for public repositories and is currently unmet on all
   of them.
3. Verify with `gh api repos/kilbertert/<repo>/rulesets`.

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
- The checkpoint that decides whether the remaining repositories are stood down
  the same way: count the Devin Review findings the operator actually fixed,
  compare it with CodeRabbit's output on the repositories that kept it, and
  revert regardless of that count if reports degrade into an explanatory
  misreport storm.
