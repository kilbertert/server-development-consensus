# QA Plan

## Scope

Verify the layered governance contract between `server-development-consensus`
and the `afk-bootstrap` execution adapter. This plan covers the policy adapter,
version compatibility, credential boundary, and structured exceptions.

## Cases

| ID | Environment | Preconditions | Test data | Actions | Expected observable result | Cleanup |
|---|---|---|---|---|---|---|
| GOV-B01 | AFK consumer repository | Adapter and consensus metadata are present | A rule that weakens the baseline | Run the adapter preflight | Preflight fails and reports the conflicting invariant | Restore test metadata |
| GOV-B02 | AFK consumer repository | CI has the compatibility validator | Current consensus outside the declared SemVer range | Run the implementation/delivery check | Check fails with both versions and no push is attempted | Restore test metadata |
| GOV-B03 | Docker agent plus host runner | Container, host wrapper, and GitHub Ruleset are available | Attempted `git push origin main` | Execute the push path at each boundary | Container check, host wrapper, and Ruleset each reject the operation | Remove temporary branch |
| GOV-B04 | AFK consumer repository | Exception validator is enabled | One valid and one expired structured exception | Run the exception check | Valid implementation exception is accepted; expired or security-boundary exception blocks delivery | Remove temporary exception records |

## Traceability

| Requirement | Feature scenario | QA case |
|---|---|---|
| Baseline precedence | An AFK adapter cannot weaken a server invariant | GOV-B01 |
| Compatibility blocking | An incompatible AFK template is blocked | GOV-B02 |
| Three-layer default-branch protection | A container cannot deliver directly to the default branch | GOV-B03 |
| Bounded exceptions | A legitimate AFK implementation difference is recorded | GOV-B04 |
| Managed Codex long context | Codex receives 872K/700K while unrelated settings survive | GOV-B05 |

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

## Risk Checks

- Complexity/coverage: not applicable; the checker is a small portable script
  covered by executable smoke cases.
- Mutation testing: not applicable; no business rule, authorization code, or
  persistence implementation changes in this decision record.

## Execution Status
