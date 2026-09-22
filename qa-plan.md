# QA Plan

## Scope

Verify the layered governance contract between `server-development-consensus`
and the `afk-bootstrap` execution adapter. This plan covers the policy adapter,
version compatibility, credential boundary, structured exceptions, and the
repository scope that decides which of those rules a repository is subject to.

## Cases

| ID | Environment | Preconditions | Test data | Actions | Expected observable result | Cleanup |
|---|---|---|---|---|---|---|
| GOV-B01 | AFK consumer repository | Adapter and consensus metadata are present | A rule that weakens the baseline | Run the adapter preflight | Preflight fails and reports the conflicting invariant | Restore test metadata |
| GOV-B02 | AFK consumer repository | CI has the compatibility validator | Current consensus outside the declared SemVer range | Run the implementation/delivery check | Check fails with both versions and no push is attempted | Restore test metadata |
| GOV-B03 | Docker agent plus host runner | Container, host wrapper, and GitHub Ruleset are available | Attempted `git push origin main` | Execute the push path at each boundary | Container check, host wrapper, and Ruleset each reject the operation | Remove temporary branch |
| GOV-B04 | AFK consumer repository | Exception validator is enabled | One valid and one expired structured exception | Run the exception check | Valid implementation exception is accepted; expired or security-boundary exception blocks delivery | Remove temporary exception records |
| GOV-B05 | Installer test fixture home | `tomlkit` is installed and `~/.codex/config.toml` carries unrelated settings | A config with existing `model`, `projects`, and approval settings | Run the installer Codex config update, then its `--verify` path | `model_context_window` is 872000 and `model_auto_compact_token_limit` is 700000, while unrelated settings and comments survive | Remove the fixture home |
| GOV-B06 | Test fixture repository classified externally governed | The managed hooks are installed and the repository has its own chained hook | Non-conventional commit message; default-branch commit; default-branch push over the repository's own remote | Run `commit-msg`, `pre-commit`, `pre-merge-commit`, and `pre-push` in the fixture | Every managed contract is skipped, the repository's own hook still runs, and the pushed hook receives the original arguments and stdin | Remove the fixture repository |
| GOV-B07 | Test fixture repository classified externally governed | A task worktree exists outside the workspace worktree location | A linked worktree placed outside the projects workspace | Run `dev-worktree audit` and `dev-policy-audit` | The worktree location violation is still reported, while server delivery lifecycle and bookkeeping findings are not raised for the external repository | Remove the fixture repository |
| GOV-B08 | Test fixture repositories with an absent or invalid class value | The managed hooks are installed | One repository with no class recorded, one with an unsupported value | Run the managed hooks and `dev-start` in each fixture | The unset fixture keeps the server-managed rules in force; the invalid fixture stops every operation with a repository class error | Remove the fixture repositories |
| GOV-B09 | Test fixture repository classified externally governed | The repository carries a local `core.hooksPath` and server delivery metadata | A local hooks path that is not the managed one, plus `serverPolicy.defaultBranch` and `branch.*.serverPolicy*` keys | Run `dev-policy-audit` and then `dev-policy-audit --repair` | Neither run fails the repository, and neither rewrites its hook configuration or its existing delivery metadata | Remove the fixture repository |
| GOV-B10 | Installer test fixture home | A checkout of the consensus source carrying the `service host` role and the migration contract | The revised canonical source | Run the canonical installer, then the policy audit | That role and that contract appear in the canonical installed copy and in every project-level policy copy; no copy drifts from the canonical source; the version contract check passes | Remove the fixture home |
| GOV-B11 | Pilot service host carrying exactly one project | The host is reachable and the project's service is running | The project's service identity and its environment file | Inspect the identity, the environment file's ownership and mode, and the host's non-loopback listeners | The identity has no login shell, no password, no sudo and no shared group; the environment file is readable by that identity and root only; the service listens on loopback; the only non-loopback listeners are SSH and the intended public entry point | None (read-only) |
| GOV-B12 | Service host and development host | A service selected for its first migration under the contract | The service's repository, its acceptance check, and its previous deployment | Move the service, switch traffic, then retire the previous instance as a separate step | Deployment assets are versioned in the repository; the acceptance result is recorded with build identity, environment and timestamp; the previous deployment keeps running until acceptance passes; traffic switch and retirement are separate steps; the exposure decision cites an observed-traffic record | Retire the previous instance only after the switch is verified |
| GOV-B13 | Enrolled repository with an observed PR-traffic record | Devin Review holds the automatic review layer and the repository is enrolled | A pull request opened, then a draft marked ready | Open the pull request, then mark the draft ready | Exactly one Devin Review appears on the ready head; no other automated reviewer comments | None (review artifact retained) |
| GOV-B14 | Enrolled repository | PR-Agent is disabled and CodeRabbit is stood down for this repository | A pull request opened | Open the pull request | No PR-Agent or CodeRabbit comment appears; the PR-Agent unit, virtualenv and credential directory remain on disk; the CodeRabbit configuration remains in the repository but inactive | None (read-only) |
| GOV-B15 | Any repository with findings on an open pull request | Devin Review findings exist on the head | The required merge gates | Evaluate the gates | Findings are advisory candidates needing human confirmation; the reviewer's own status check is never required; deterministic CI and the Ruleset decide the merge | None (read-only) |
| GOV-B16 | Task branch with auto-fix enabled | Auto-fix has pushed a fix commit to the remote task branch; the local worktree holds uncommitted work | An uncommitted change on the task branch | Commit the work, then fetch and rebase on the remote task branch, then push | The rebase runs only once the tree is clean, the fix commit is integrated, nothing is force-pushed, and no uncommitted work is discarded to make the rebase run | Remove the temporary branch |
| GOV-B17 | Development host workspace with a policy audit reporting stale branches | The audit reports one or more local task branches as `upstream_gone` or `integrated_not_retired` | Local task branches across the scanned repositories | For each branch, verify the head carries a merged pull request and that the branch tree matches its hosting merge commit, then retire the local branch, and the remote ref where one still exists | No branch is retired without a verified merge; the audit then reports `stale_branches=0`; remote ref deletion and local branch deletion are reported as separate operations | None (retirement is the operation) |
| GOV-B18 | Development host with a self-hosted runner | A job checkout exists under `_runners/<runner>/_work/` and a deploy checkout exists under `_runners/`, neither carrying delivery metadata; one runner checkout is unreadable; two controls sit outside `_runners/` | The runner, deploy and unreadable fixtures in `tests/test-dev-policy-audit.sh`, plus a repository in a `_work` directory and a project with no metadata, both outside `_runners/` | Run `dev-policy-audit` over the projects root | All `_runners/` artifacts are reported as `skip runner working directory` and none fails, including the unreadable one, while both controls still fail with `default-branch expected=main actual=unset` | Remove the fixture repositories |
| GOV-B19 | Repository whose Ruleset requires conversation resolution | A pull request carries an unresolved Devin Review thread; all required checks pass | A real pull request against a gated repository (`AI-Ops#371`, merged `229cc194`) | Read `mergeStateStatus` with all required checks passing while threads are unresolved and again once resolved; attempt the merge while blocked; resolve a thread by hand; post the triage record and request the re-review | `BLOCKED` with unresolved threads under all-checks-passing and `CLEAN` once every thread is resolved (`14 of 14` at merge); `gh pr merge` refused with `the base branch policy prohibits the merge`; a write-access user resolves a thread and returns `resolvedBy: kilbertert`; after the re-review Devin resolves the thread it considers fixed and leaves the accepted-limitation thread unresolved | None (the gate is the state under test) |

## Traceability

| Requirement | Feature scenario | QA case |
|---|---|---|
| Baseline precedence | An AFK adapter cannot weaken a server invariant | GOV-B01 |
| Compatibility blocking | An incompatible AFK template is blocked | GOV-B02 |
| Three-layer default-branch protection | A container cannot deliver directly to the default branch | GOV-B03 |
| Bounded exceptions | A legitimate AFK implementation difference is recorded | GOV-B04 |
| Managed Codex long context | Codex receives 872K/700K while unrelated settings survive | GOV-B05 |
| External delivery scope | An externally governed repository keeps its own delivery process | GOV-B06 |
| Host boundaries still apply | Host boundaries still apply to an externally governed repository | GOV-B07 |
| Class fails closed | An unrecorded repository class stays server-managed; an unreadable or invalid repository class fails closed | GOV-B08 |
| Delivery metadata not maintained | An externally governed repository keeps its own delivery process | GOV-B09 |
| Service host model installed | The service host model is present in every installed policy copy | GOV-B10 |
| Service identity scope | A service identity is scoped to one project | GOV-B11 |
| Migration contract | A move is not complete when the new deployment starts serving | GOV-B12 |
| One first-pass reviewer | An enrolled repository receives one automated review | GOV-B13 |
| Retired reviewers stand down | A retired reviewer is stood down rather than deleted | GOV-B14 |
| Review remains advisory | Automated review is never a merge gate | GOV-B15 |
| Auto-fix integration | An auto-fix commit does not strand the task branch | GOV-B16 |
| Stale delivery surface retired | A merged task branch is retired from the local workspace | GOV-B17 |
| Deployment artifacts are not projects | A runner working directory is not a managed repository | GOV-B18 |
| Triage is gated, the reviewer is not | An untriaged finding cannot be merged past | GOV-B19 |
| The re-review closes the loop | Requesting the re-review is what closes the triage loop | GOV-B19 |

## Execution Results

Status: passed on `2026-08-28T23:25:32+0800`.

GOV-B10 through GOV-B12 were added with the `service host` model and have not
been executed yet. GOV-B12 becomes executable when the first service is moved
under the migration contract; until a case has a recorded result, it is not
evidence and must not be reported as passed.

GOV-B13 and GOV-B14 were added with the Devin Review migration and were
executed on the first pull requests raised on an enrolled repository after the
migration; their results are recorded below, with `GOV-B13` passing on its
ready-on-open path only. GOV-B15 became executable once
`server-development-consensus` gained the Ruleset that gives an advisory finding
something to be compared against, and is recorded below. GOV-B16 stays
unexecuted because auto-fix has not pushed a commit to a task branch. Until a case has a recorded result,
it is not evidence and must not be reported as passed.

GOV-B17 was added with the first full delivery-surface sweep and was executed
on that sweep; GOV-B18 was added with the audit fix that sweep produced and was
executed as the case's fixtures. Both results are recorded below. GOV-B17 is
executed again whenever the daily audit reports a stale branch; the result below
records the sweep that cleared every finding, not a standing state.

GOV-B19 was added with the triage gate. It ran as a canary on `AI-Ops` first,
the gate was held on that repository alone until the result was read, and it was
then extended to every repository carrying this server's Ruleset. The sequence
matters and is recorded in that order below rather than rewritten as one
completed state: the intermediate "canary only" status was true when written.

GOV-B15's expected result was corrected in the same change: it previously said
deterministic CI and the Ruleset *alone* decide the merge, which the triage gate
makes false.

### GOV-B13 and GOV-B14 - one first-pass reviewer, retired reviewers stood down

Executed on `2026-09-21` from the `claude` development host against
`kilbertert/AI-Ops`, the first enrolled repository to receive a pull request
after the migration. `GOV-B14` passed. `GOV-B13` passed on the ready-on-open
path only. Two pull requests carry the observation:

- `kilbertert/AI-Ops#349`, head `f6d7ae8f6cdc4efe987526831125bdcc50c22a92`,
  raised `2026-09-21T08:30:46Z`: one `devin-ai-integration[bot]` review
  (`COMMENTED`, `2026-09-21T08:32:22Z`), zero `coderabbitai[bot]` comments or
  reviews.
- `kilbertert/AI-Ops#350`, head `f91db213c679817d1cff16ff010130d8ba681ae2`,
  raised `2026-09-21T08:50:35Z`: one `devin-ai-integration[bot]` review
  (`COMMENTED`, `2026-09-21T08:51:49Z`), zero `coderabbitai[bot]` comments or
  reviews.

The contrast that makes the result mean something is
`kilbertert/AI-Ops#345`, raised before the cutover, which carries both Devin
Review and CodeRabbit on the same pull request.

The stand-down is observed rather than assumed: `pr-agent.service` is
`disabled` and `inactive`, port 8766 is unbound, and the unit, launcher,
virtualenv and credential directory remain on disk at
`~/.config/systemd/user/pr-agent.service`, `~/.local/libexec/pr-agent-start`,
`~/.local/share/pr-agent/` and `~/.config/pr-agent/`.

### GOV-B15 - automated review is never a merge gate

Executed on `2026-09-21` on `kilbertert/server-development-consensus`, which
carries the Ruleset `protected default branch` on `~DEFAULT_BRANCH` with
`bypass_actors: []`, `current_user_can_bypass: "never"` and
`required_status_checks` under `strict_required_status_checks_policy: true`.

Pull request #34 separates the two kinds of signal in its check rollup:
`Governance release unit` reports `isRequired: true` as a `CheckRun`, while
`Devin Review` reports `isRequired: false` as a `StatusContext`. Devin Review
posted two findings on that head, one of them `kind: bug`, and the pull request
stayed mergeable: the pending advisory check produced `mergeStateStatus:
UNSTABLE` rather than `BLOCKED`. The deterministic CI job was the only required
check, so CI and the Ruleset decided the merge while the findings stayed
candidates for a human.

One finding was resolved: the conflict between this plan and `qa-plan.md` was
fixed in this change. The second was triaged and its remedy applied: the fork
gate on `AI-Ops` was a real limitation, the remedy was to move `verify` back to
a GitHub-hosted runner, and `kilbertert/AI-Ops#351` did exactly that (merged as
`48773b7`, `verify` passing on `ubuntu-latest`).

Triage here rests on configuration evidence, not on an observed fork pull
request: the guard is deleted from the workflow, `verify` runs on
`ubuntu-latest`, the required check list is unchanged, and the three workflows
that stay on the self-hosted runner produce no pull-request check. This is
enough to say the fork path no longer reaches a required gate; it is not an
observation that forks now pass, and the difference is recorded rather than
smoothed over.

Not yet observed, recorded rather than implied:

- No fork pull request has been raised against `AI-Ops` since the gate was
  removed, so the fork path is closed by configuration only.
- The draft-to-ready trigger path in `GOV-B13`: both pull requests were raised
  ready, so the case is passed on its ready-on-open path only.
- The no-CodeRabbit half of `GOV-B14` on `Auto_Test` and `genesis-evidence`: no
  pull request has been raised there since the cutover, so the same observation
  does not yet exist outside `AI-Ops`.

- Consensus contract test passed on merge commit
  `19652f60f9732ff7f307d9c6f6e4e3acb7663a1a`; CI run
  [33183183670](https://github.com/kilbertert/server-development-consensus/actions/runs/33183183670)
  passed.
- AFK smoke tests passed for Node and Python, including compatible and bounded
  exception cases and default-branch rejection.
- Consumer PRs #144, #78, #124, and #62 merged after their deterministic checks
  passed; final `origin/main` SHAs are recorded in the AFK QA plan.

### GOV-B05 - managed Codex long context

Passed locally on `2026-09-18T20:38:01+08:00` on the `claude` development host. The repository's full
CI check set was run on this branch: `tests/test-ai-review-policy.py`,
`test-afk-contract.sh`, `test-dev-worktree.sh`, `test-pre-push.sh`,
`test-commit-msg.sh`, `test-dev-policy-audit.sh`, `test-install.sh`, and the
Review Sentinel unit and installer tests. `test-install.sh` and
`test-update-codex-config.sh` assert the 872000/700000 defaults and that
unrelated settings survive. The authoritative result is this change's
`Governance release unit` CI run.

### GOV-B06 - GOV-B09 - repository class

Passed locally on `2026-09-18T22:00:46+08:00` on the `claude` development host.
`tests/test-commit-msg.sh`, `tests/test-pre-commit.sh`,
`tests/test-pre-merge-commit.sh`, and `tests/test-pre-push.sh` cover the hook
scope and the project-hook forwarding; `tests/test-dev-worktree.sh`,
`tests/test-dev-policy-audit.sh`, `tests/test-dev-start.sh`, and
`tests/test-dev-pr.sh` cover the task lifecycle, the audit exemptions, and the
GitHub-only command. The repository's full local check set passed on commit
`ed760d4`. The authoritative result is this change's `Governance release unit`
CI run:
[35353503061](https://github.com/kilbertert/server-development-consensus/actions/runs/35353503061).

### GOV-B17 - stale task branches retired after verified integration

Executed on `2026-09-21` on the `claude` development host. The audit reported
`stale_branches=16` across six repositories: `RedInk` 3, `afk-bootstrap` 3,
`genesis-evidence` 6, `sports-ability` 2, `borderless-business-days` 1 and
`ds408-visualizer` 1. An earlier pass the same day had cleared the seven
`[gone]` branches in `AI-Ops` under the same check.

Every branch was verified before deletion:

- the head carries a **merged** pull request
  (`gh api repos/<slug>/commits/<sha>/pulls`);
- the hosting merge commit is an ancestor of `origin/<default>`;
- `git diff <branch-tip> <merge-commit>` is empty, so the branch tree is the
  tree the hosting service merged. Fifteen of the sixteen were byte-identical;
  `RedInk feat/provider-psydo-image` differed by a `CLAUDE.md` that the merge
  commit inherited from the base branch, so the difference is content the branch
  did not author and did not lose.

Result: 23 local branches retired in one day (7 in `AI-Ops`, then 16 across the
six). Six of the 16 still had a live remote ref (`RedInk` ×3, `genesis-evidence`
×3), each confirmed identical to the local tip, and those were deleted as a
separate, separately reported operation. No worktree was involved: every
affected repository had only its canonical checkout. Nothing was pushed.

The reading is a moving one, and this record keeps it so. While the audit fix in
`GOV-B18` was being prepared, a concurrent AFK run merged `AI-Ops`
`chore/prd-run-identifies-its-sub-issue` (PR #352, merge `c59105b`) and deleted
its remote, so the audit reported it. It was verified by the same three checks
and retired; its task worktree was live on a different branch (`#347` open) and
was left alone. A linked worktree contributes its shared `refs/heads` to the
scan, so that one branch read as `stale_branches=2`, once under `AI-Ops` and
once under `.worktrees/AI-Ops-prd-325-merge`. That double reading is recorded
here as an observation, not fixed in this change.

The reading kept moving, as the record above says it would. While this change was
under review, the concurrent AFK run's task branch `agent/prd-325-prd-sql` was
merged (PR #347, merge `12d0818`) and its remote deleted, so the audit reported
`stale_branches=2` again — the same branch under `AI-Ops` and under its linked
worktree, which is the double reading above. Its worktree was still live on a
different branch, so it was left alone; the branch itself passed the same three
checks (merged PR, merge commit an ancestor of `origin/main`, empty tree diff)
and was retired. The final reading after the fix and this second sweep is
`failures=0 repaired=0 stale_branches=0`.

### GOV-B18 - a runner working directory is not a managed repository

Executed on `2026-09-21` on the `claude` development host. `dev-policy-audit`
failed every run with a `default-branch expected=main actual=unset` finding
against the path `/home/claude/Projects/_runners/AI-Ops-runner/_work/AI-Ops/AI-Ops`.
That checkout is a job's, created by the runner; the installer never manages it, so it never carries
`serverPolicy.defaultBranch`, and a rule that reads the hosting service's default
branch and then demands matching local metadata is not a statement about it.
`--repair` cannot settle it durably either, because the next job replaces the
checkout.

Fix: the runner-checkout predicate, until then private to `dev-worktree`, moved
into `lib/dev-git-common.sh` so the worktree layer and the delivery-metadata
layer share one definition, and the audit now reports such paths as
`skip runner working directory` rather than auditing them.

The adversarial review of this change produced two corrections, both confirmed
and both fixed here, and both are why the predicate's scope is stated so
narrowly:

1. **The predicate was a blanket exemption.** Moved code keeps its old bugs, and
   this one widened as it moved: a bare `*/_work/*` clause sat beside the
   `_runners/` clause, matching a `_work` directory anywhere on the filesystem.
   Under the worktree layer that clause governed only a detached-HEAD note; under
   the audit it grew into an exemption from every managed-repository rule, so
   `/home/claude/Projects/customer/_work/api` audited as a deployment artifact
   and its missing delivery metadata went unreported. Measured on the host: the
   path was reported as `skip runner working directory` and the audit reported
   `failures=0` for it. Every runner root here declares its working directory
   under `_runners/` (five `active` units, `workFolder: _work`), so the `_work`
   clause carried no path the `_runners/` clause did not already carry; it was
   removed rather than scoped. The same path now fails with
   `default-branch expected=main actual=unset`, which is the assertion
   `tests/test-dev-policy-audit.sh` pins.
2. **The skip ran after the state read.** The predicate was called only once
   `git branch` and `git status` had succeeded, so a job reclaiming its checkout
   between the inventory and the read turned a deployment artifact into
   `FAIL <path> cannot inspect repository state` and incremented `failures`.
   Measured on the host with an unreadable fixture: old order reported that
   `FAIL`; new order reports `skip runner working directory` and `failures=0`.
   The predicate now runs before any repository state command, and the branch
   field is best-effort.

Evidence: `tests/test-dev-policy-audit.sh` creates a runner job checkout and a
deploy checkout under `_runners/`, asserts both are reported as skipped and
neither fails; makes a runner checkout unreadable and asserts it is still
skipped rather than failed; and creates two controls outside `_runners/` — a
repository in a `_work` directory and a project with no delivery metadata at all
— asserting both still fail with `default-branch expected=main actual=unset`.
So the exemption is scoped rather than a blanket relaxation. On the host the
audit moved from `failures=1` to `failures=0`.
`tests/test-dev-worktree.sh` passes unchanged, which is the check that moving
the predicate left the worktree-layer behaviour alone. The release unit is
`1.8.1`.

### GOV-B19 - triage is gated, the reviewer is not

Executed on `2026-09-22`. This case exists because of a measurement, not a
design preference: the rule "a human must confirm severity and applicability"
was enforced by nothing, so it did not happen.

The measurement, over pull requests created on or after the reviewer was
connected:

| Repository | Pull requests with findings | Triaged | Merged past |
| --- | --- | --- | --- |
| `server-development-consensus` | 7 | 6 | 1 |
| `AI-Ops` | 8 | 1 | 7 |
| `genesis-evidence` | 1 | 0 | 1 |
| `Health-Flow` | 1 | 0 | 1 |

The latency separates the two populations cleanly: every triaged pull request
was merged at least 276 seconds after the review, every merge-past within 268
seconds, half within 120. `Health-Flow#104` is the clearest instance — the head
never moved, three findings received no reply, and the merge came 84 seconds
after the review posted. A review merged past in under 90 seconds was not read.

The gate is `required_review_thread_resolution: true` on the existing Ruleset.
Applied first to `AI-Ops` (ruleset `23760870`), which carries both the worst
ratio and a real pull-request check to keep required; the other five enrolled
repositories follow only if this canary passes.

The distinction the gate rests on, verified rather than asserted:

- **The reviewer's status check stays non-required.** `Devin Review` is a
  `StatusContext`; `verify`, `windows-verify` and `Workflow policy` remain the
  required `CheckRun`s. A vendor outage opens no thread and so costs no merge
  availability, which is precisely what requiring the status check would have
  broken.
- **A human can resolve a thread.** Exercised on a merged, inert pull request
  (`server-development-consensus#38`): a thread Devin had left unresolved was
  resolved by `kilbertert` and then unresolved again, so no false record was
  left behind. The mutation returned `resolvedBy: kilbertert`. The reviewer
  therefore cannot hold a branch hostage.
- **Resolution is not automatic.** This is the finding that changed the shape of
  the change. Across 11 pull requests the correlation is exact: every head that
  received an explicit `/devin review` had its threads resolved by
  `devin-ai-integration[bot]`; every head that did not received zero resolutions
  (`AI-Ops` 4 pull requests carrying 10 threads, 0 resolved; `consensus#38`,
  1 thread, unresolved). A triage comment alone resolved nothing — on
  `consensus#37` the comment and the `/devin review` posted one second apart,
  and only the re-review produced the resolutions. The gate is therefore
  satisfied by requesting the re-review, which is the same action the policy
  already requires of the responsible agent.

One failure mode the gate does **not** catch, recorded rather than smoothed
over: `AI-Ops#344` and `#360` were merged 23 and 19 seconds after being marked
ready, before the review had posted at all, so no thread existed to block. The
reviewer responds in 1-2 minutes consistently, so this is a race against the
review's arrival, not reviewer latency. The mitigation is the existing
convention — do not merge a pull request that was just moved out of draft until
its review has posted — and `AI-Ops`' own agent already treats unresolved
threads as its work queue, but never posts the re-review that would close them.

#### Canary observation: `kilbertert/AI-Ops#371`

Two things are recorded here, and they carry different weight. The **result** is
solid; the **per-row readings** are not, and the difference is stated rather than
smoothed over.

**Result (verified).** The gate blocked the pull request repeatedly while findings
were unresolved, and released it when they were not. `#371` was merged on
`2026-09-22T07:03:54Z` as `229cc194` with **14 of 14 review threads resolved**,
each carrying a written disposition. Before that merge, with all three required
checks (`Workflow policy`, `verify`, `windows-verify`) reporting `pass` and
`mergeable: MERGEABLE`, the pull request read `BLOCKED` and
`gh pr merge --squash` was refused with `the base branch policy prohibits the
merge`. When every thread was resolved under the same check state it read
`CLEAN`. Both were read directly from `gh pr view`/`gh pr checks` on the pull
request.

**Per-row readings (not substantiated — treat as withdrawn).** Earlier versions
of this record carried a table of thread counts against specific heads, including
a claimed controlled comparison at one head where only thread state varied. That
table cannot be substantiated and is removed rather than corrected again:

- It named head `49622e29`, which is a commit of this work's own against which
  **no review finding was ever raised** — the pull request's review-comment
  records show zero findings at that head. Rows describing "0 of 1" and "1 of 1"
  there were describing a state in which nothing was under test.
- Rewriting it from the review-comment records produced counts that did not match
  the head (`86bae95` carries four findings, not the two the replacement claimed).

Two reconstruction attempts failed, so the readings are withdrawn instead of
being patched a third time. **What this costs:** there is no per-head record here
of a thread-count-versus-`mergeStateStatus` sweep, so the claim that a *partial*
state blocks is not evidenced by this record — only that unresolved threads block
and full resolution releases. The `BLOCKED`/`CLEAN` result above does not depend
on the withdrawn rows. A future canary that wants a controlled comparison should
capture `gh pr view --json mergeStateStatus` alongside `gh pr checks` at each
step as it goes, rather than reconstructing them afterwards.

An earlier reading is recorded because it was **invalid and had to be discarded**:
`BLOCKED` was first observed while `windows-verify` was still `pending`, which is
independently sufficient to produce `BLOCKED`. Attributing the gate to that
reading would have been a false claim, so the readings above were taken only
after every required check had completed.

Both manual resolutions in this sequence were performed by `kilbertert` and
returned `resolvedBy: kilbertert`, re-confirming the escape hatch on a gated
repository rather than only on an inert merged one.

The loop then closed as the mechanism predicts: after the triage record and a
`/devin review` request, Devin resolved the thread covering the finding that was
actually fixed and left the thread covering the finding recorded as accepted
unresolved — independently demonstrating the limitation described below.

Two limitations rest on this canary and are not resolved by it:

- **The gate does not prove a human read the finding.** It requires a resolved
  thread, and a re-review resolves threads in bulk, so it cannot require that the
  resolver read the finding or wrote a reason. What it does is make an untriaged
  finding cost something; on this very canary, Devin resolved one thread and left
  the other, so the distinction between "fixed" and "recorded as accepted" stayed
  visible at least to the reviewer. Recorded as a known boundary of the chosen
  mechanism rather than smoothed over.
- ~~**The gate is canary-only.**~~ Closed by the rollout recorded below. It was
  true when written and is kept here as the state the change passed through,
  struck through rather than deleted so the sequence stays readable.

#### Rollout to the remaining repositories

The canary passed (recorded above), so the gate was extended. The change was
made with the minimal round-trip — fetch the whole rule set, change the one key,
PUT it back — and **verified by reading the value back**, not by trusting an exit
code, because the canary produced a defect that exited `0` while changing nothing.

| Repository | Ruleset | Result |
| --- | --- | --- |
| `AI-Ops` | `23760870` | already enabled (canary) |
| `server-development-consensus` | `23760245` | enabled; other rules and conditions unchanged |
| `genesis-evidence` | `23760874` | enabled; other rules and conditions unchanged |
| `newenergy-ai-article-platform` | `23760875` | enabled; other rules and conditions unchanged |
| `ds408-visualizer` | `23760876` | enabled; other rules and conditions unchanged |
| `Auto_Test` | `23760872` | **found already enabled, created/enabled outside this work** |
| `Health-Flow` | `23809254` (new) | ruleset created with the gate included |

`Auto_Test` is recorded as found rather than as changed by this work. Its ruleset
reports `updated_at 2026-09-22T11:45:59+08:00`, which is not a time this work
touched it, and the rollout script reported `already true; nothing to do` without
writing. Who enabled it is not established here; recording it as this change's
work would be an unverified claim. The value is `true` either way, which is what
the policy requires of the repository.

`Health-Flow` had **no ruleset at all** — it is public, so the Phase 4 rule
applied to it and had been missed. `Health-Flow#104` was merged 84 seconds after
a review carrying three unread findings with nothing enforcing anything, which is
what a public repository with no ruleset permits. Its ruleset was created with
the same four rules and with the triage gate included from the start (there was
no prior setting to preserve), `bypass_actors: []`,
`current_user_can_bypass: never`, and `Workflow policy` as the required check —
verified as the only workflow that actually triggers on `pull_request` in that
repository, since requiring a check that never fires would block every merge
permanently.

**Every repository that carries this server's Ruleset now requires conversation
resolution.** Being precise about the set, because an earlier version of this
paragraph said "all six enrolled repositories" and conflated two different sets:

- The **enrolled set for Devin Review** is four repositories — `AI-Ops`,
  `Auto_Test`, `server-development-consensus`, `genesis-evidence` — defined by
  observed pull-request traffic in `docs/devin-review-migration.plan.md`.
  `newenergy-ai-article-platform` and `ds408-visualizer` are enrolled when their
  next pull request arrives, and `sports-ability` stays out deliberately.
- The set that carries the `protected default branch` Ruleset is those four plus
  `newenergy-ai-article-platform`, `ds408-visualizer` and `Health-Flow`.

The gate belongs on **every repository whose merges this server controls**, not
only on the enrolled ones: an unresolved finding blocks a merge whether or not
the repository is enrolled, and a repository that is not yet enrolled is exactly
the one that will be. So the change covers the seven repositories above, and the
statement the policy text needs is the one true of all of them — no repository
under this server's Ruleset merges past an unresolved thread.

#### Canary outcome

The canary passed and the gate is live on `AI-Ops`. `kilbertert/AI-Ops#371` was
merged on `2026-09-22T07:03:54Z` as `229cc194`, with **14 of 14 review threads
resolved**, every one carrying a written disposition.

The number that matters is not 14 — it is what the gate forced out of the way.
The pull request was blocked by its own gate through seven review rounds, and
each round produced findings that were real:

- A documented **verification step that would really have merged the observation
  pull request** (`gh pr merge` without `--auto` executes the merge on a
  `BLOCKED` pull request, so a failed test would have modified the default branch).
- A "hardened" shell script whose rewritten form **silently never enabled the
  gate**: it PUT an unchanged rule set, exited `0`, and reported success while
  `required_review_thread_resolution` stayed `false`. It survived its own test
  suite because that suite asserted exit codes rather than outcomes.
- Two documents that were each true alone and contradicted each other.
- A milestone record that claimed behaviour evidence its own validation section
  still described as unobserved.

The mechanism's shape was revised because of this: the four-step, single-boolean
operation had grown ~80 lines of shell and three embedded `python` blocks, and
each round of hardening introduced a new defect. The script was deleted in favour
of the minimal `gh api` round-trip plus one deterministic acceptance — read the
value back and see `true` — which is what the `/ai-ops` record now documents.

Four findings were raised repeatedly and closed as triaged rather than re-edited:
the mechanism cannot prove a human read a finding (accepted limitation); the
concurrent-write window is covered by a stated cost rather than `If-Match`
(accepted risk); remote configuration is not managed by the commit, which is
answered with a re-runnable read-only check rather than versioning the state; and
the `BLOCKED` attribution is now scoped to the current rule set with the
rule-set query retained as evidence. Those dispositions are on the pull request.

## Risk Checks

- Complexity/coverage: not applicable; the checker is a small portable script
  covered by executable smoke cases.
- Mutation testing: not applicable; no business rule, authorization code, or
  persistence implementation changes in this decision record.

## Execution Status
| DH-B01 | Real target with a recorded host key | A project declaration resolves to a recorded host; the recorded key is deliberately wrong | Any read against that target | Run the read | Refused with a host-identity failure; no command output; the host is not contacted | None |
| DH-B02 | Real or fixture service-class target | Target role is service-class | A file written without `--artifact-sha256` | Run the write | Refused; the message states the artifact identity is the release condition; nothing is transferred | None |
| DH-B03 | Fixture service-class target | Target role is service-class | A file whose artifact hash does not match the declared one | Run the write with a mismatched artifact identity | Refused; the message reports the actual hash | None |
| DH-B04 | Fixture host recorded with a non-SSH access method | Host record marks access as `rdp` or equivalent | Any operation | Run the operation | Refused as unsupported without attempting a connection | None |
| DH-B05 | Fixture declaration | Target names a host absent from the private record | Any operation | Run the operation | Refused; the host is not contacted | None |
| DH-B06 | Fixture declaration | Declaration file is unreadable or not valid TOML | Any operation | Run the operation | Treated as absent and refused, never silently allowed | Restore the declaration |
| DH-B07 | Real target on a service host | Deployment steps from the project runbook | A built artifact with a known SHA-256 | Follow backup → transfer → verify → restart | Transfer refused without artifact identity and accepted with it; per-file SHA-256 comparison produced by the tooling rather than by hand | Remove temporary files on the target |
