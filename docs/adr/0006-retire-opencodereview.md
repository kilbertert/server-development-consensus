---
status: accepted
---

# Retire OpenCodeReview

The server's review architecture named three layers, and the first of them was a
local one: `ocr review`, the OpenCodeReview CLI, run by Codex or Claude during
the development loop. On 2026-10-08 the owner directed that it be removed rather
than repaired: "we are not using this any more". This ADR records what was
measured before acting, because a layer that never worked looks exactly like a
layer nobody needed, and only one of those justifies deletion.

## What was measured

The local layer was not dead the way PR-Agent had been dead — it ran. The
gateway log for the development host's model relay (`~/.cli-proxy-api/logs/`,
2026-10-08) shows `User-Agent: open-code-review/v1.12.12 | claude` requests
against `http://127.0.0.1:8317`, reaching the model as `deepseek-latest` and
being answered. So the tool worked end to end through the local provider; it was
retired on the owner's decision, not on a defect finding.

Two facts made retirement cheap rather than merely desired:

1. **Nothing depended on it.** `install.sh`, `lib/`, `policy/`,
   `bin/dev-policy-audit`, and `bin/dev-pr-review` contain no reference to the
   OCR CLI. Its only entry points were the policy text, the stored agent
   instructions, the npm global package, and one legacy GitHub Action file in a
   separate repository (`ranlei-blog-ledger-operations`, itself a branch-parked
   work-in-progress whose remote default branch this change does not touch).
2. **It was already declared non-essential.** The policy already called AI
   findings advisory, already kept the reviewer's status check out of the merge
   path, and already stated that deterministic CI and the Ruleset are the only
   mandatory gates. Removing the local layer removes a convenience, not a
   control.

## Decision

OpenCodeReview is retired from the server. Concretely:

- The `ocr` CLI is uninstalled (npm global package
  `@alibaba-group/open-code-review` and the `~/.local/bin/ocr` link), the Codex
  marketplace and plugin registration are removed, and the retired Codex
  instruction that pointed agents at `ocr review` is deleted as part of the same
  release unit — leaving it installed "disabled" is exactly what already
  happened to PR-Agent and is the state this decision rejects repeating.
- The policy and both agent-facing documents describe a **two**-layer
  architecture: Devin Review for the automatic pull-request review, CI/Ruleset
  as the only mandatory gate. The local loop has no dedicated review tool; the
  responsible agent's own reading of the diff, plus its tests and static checks,
  is the local review.
- Reintroducing a local reviewer is a **separate decision that has to bring its
  own acceptance evidence**. It is not a reinstall, and it is not a repair to
  make while touching something else.

The review budget for a logical milestone drops from "a local OCR pass, one
automatic Devin Review, and at most one re-review" to "one automatic Devin
Review and at most one re-review". The thread loop, the triage gate, the
non-required reviewer check, and the auto-fix rebase rule are unchanged.

## Consequences

- A change that Devin Review filters out (a documentation-only pull request, for
  one) no longer has a second machine opinion behind it. That was always true of
  the local pass as well — OCR selected files by extension and path rules, so a
  filtered change was reported as a clean run rather than an unreviewed one —
  but the coverage-measurement discipline that guarded against reading "clean"
  as "reviewed" goes with the tool. The remaining protection is that the
  responsible agent states what it actually reviewed, and a human reads the
  recorded disposition at the pull request.
- Reviews now happen later: at the pull request rather than at the milestone.
  This is a real cost accepted deliberately, and it is the reason the local
  layer is retired as a whole rather than trimmed to a smaller budget.
- `tests/test-ai-review-policy.py` is fail-closed on the layer count, so the
  documentation and its assertions move together in one change.

## Supersedes

`docs/devin-review-migration.plan.md` Phase 2 item 4, which retained `ocr review`
as the local pre-PR tool. That phase's reasoning — that a local tool does not
occupy the first-pass PR slot — was correct about the slot and beside the point
about the tool: the local layer is retired because the owner does not want it,
not because it collided with Devin Review.
