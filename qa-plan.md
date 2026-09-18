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

## Execution Results

Status: passed on `2026-08-28T23:25:32+0800`.

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
