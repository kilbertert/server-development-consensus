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
| GOV-B19 | Enrolled repository whose Ruleset requires conversation resolution | A pull request carries an unresolved Devin Review thread | A real pull request against the gated repository (`AI-Ops#371`, head `49622e29` / `4edbfb9` / `86bae95`) | Read `mergeStateStatus` with all required checks passing, at 0, 1 and 2 resolved threads and back to 1; attempt the merge while blocked; resolve a thread by hand; then post the triage record and request the re-review | `BLOCKED` at 0 and 1 resolved threads and `CLEAN` at 2, on one unchanged head with unchanged checks; `gh pr merge` refused with `the base branch policy prohibits the merge`; a write-access user resolves a thread and returns `resolvedBy: kilbertert`; after the re-review Devin resolves the thread it considers fixed and leaves the accepted-limitation thread unresolved | None (the gate is the state under test) |

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

GOV-B19 was added with the triage gate and was executed as a canary on
`AI-Ops` before the gate was extended to any other repository. Its result is
recorded below, and the gate stays on `AI-Ops` alone until that result is read.
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

The behavioural evidence, on a real pull request against the gated repository.
The four observations were taken across the branch's life, at these heads, with
the head recorded per row rather than claimed to be constant:

| Head | Threads resolved | `mergeStateStatus` |
| --- | --- | --- |
| `49622e29` | 0 of 1 | `BLOCKED` |
| `49622e29` | 1 of 1 | `BLOCKED` |
| `49622e29` | 1 of 1, then re-unresolved to 0 of 1 | `BLOCKED` |
| `4edbfb9` | 0 of 2 | `BLOCKED` |
| `4edbfb9` | 1 of 2 | `BLOCKED` |
| `86bae95` | 2 of 2 | `CLEAN` |

Reading the table correctly requires one care: the first three rows are the
controlled comparison, because they are the **same head with unchanged checks**
and differ only in thread state. Row 2 is the partial state (one of two threads
resolved) and row 3 is the re-unresolving that re-blocked a pull request whose
checks had not moved. The remaining rows are re-reads after the head advanced,
so they corroborate the gate but are not single-variable comparisons against the
first three.

Every reading was taken with all three required checks (`Workflow policy`,
`verify`, `windows-verify`) reporting `pass` and `mergeable: MERGEABLE`, so no
pending check can account for any `BLOCKED` in the table.

`gh pr merge --squash` in the blocked states was refused with `the base branch
policy prohibits the merge`. The second and fourth rows are the ones that matter:
a partial state still blocks, and re-unresolving a single thread re-blocks a pull
request whose checks have not changed at all.

An earlier reading is recorded because it was **invalid and had to be discarded**:
`BLOCKED` was first observed while `windows-verify` was still `pending`, which is
independently sufficient to produce `BLOCKED`. Attributing the gate to that
reading would have been a false claim, so the observation was repeated after the
check completed. Every reading in the table above post-dates that.

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
- **The gate is canary-only.** Only `AI-Ops` carries it. The other five enrolled
  repositories still merge unresolved findings, and the policy text now states a
  rule those repositories do not yet enforce. Extending it is the next step, and
  until it happens the gap is stated here rather than implied to be closed.

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
