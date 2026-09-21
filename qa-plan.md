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
| GOV-B15 | Any repository with findings on an open pull request | Devin Review findings exist on the head | The required merge gates | Evaluate the gates | Findings are advisory candidates needing human confirmation; deterministic CI and the Ruleset alone decide the merge | None (read-only) |
| GOV-B16 | Task branch with auto-fix enabled | Auto-fix has pushed a fix commit to the remote task branch; the local worktree holds uncommitted work | An uncommitted change on the task branch | Commit the work, then fetch and rebase on the remote task branch, then push | The rebase runs only once the tree is clean, the fix commit is integrated, nothing is force-pushed, and no uncommitted work is discarded to make the rebase run | Remove the temporary branch |

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
