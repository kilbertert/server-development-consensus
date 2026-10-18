---
status: accepted
---

# Retire Review Sentinel

The server's review architecture has a review-only, self-hosted GitHub App layer
in the governance repository itself: `review-sentinel/`, described since
2026-08-18 as "the governance repository's minimal self-hosted implementation".
On 2026-10-18 the owner directed that it be cleaned up completely.

This ADR exists because retiring it is not the same act as retiring a tool that
merely stopped running. `review-sentinel/` is **source in this repository**, and
the policy document, both agent-facing documents, the CI workflow, and a
fail-closed test all name it. Removing the files without the documents would
leave the policy describing a layer whose implementation is gone; removing the
documents without the files would leave an unreferenced service tree. They move
together, in one change.

## What was measured

The ADR 0006 precedent applies directly: *"a layer that never worked looks
exactly like a layer nobody needed, and only one of those justifies deletion."*
So the state was measured before acting.

**It never processed a single successful review.** The durable queue
(`~/.local/state/review-sentinel/review-sentinel.sqlite3`) holds exactly seven
jobs, every one of them `status = failed`, all against one repository
(`kilbertert/helixent-agent-wo`), all created and failed inside a single
23-minute window on 2026-07-30. The database was last written **2026-07-30** —
80 days before this decision.

**Its GitHub App was never installed anywhere.** The App exists
(`ranlei-code-review-app-2026`, id `4435133`) and reports
`installations_count: 0`. It was created, and never installed on a single
repository. Its `github-app-manifest.json` describes a deliberately narrow
permission set (contents read, pull requests read, issues write; no actions,
checks, workflows, or administration) — a design that was never exercised
against a real installation.

**The service never ran under a service manager in earnest.**
`review-sentinel.service` was `disabled`/`inactive`; the installer's own
documented contract is that it "never enables or starts the user service", so
this was the expected resting state, not a fault.

Two facts made retirement cheap rather than merely desired:

1. **The policy already treats it as out of service.** The policy text says it
   "stays disabled rather than being brought into service", with Devin Review
   holding the automatic review layer. Its retirement removes a declared-inactive
   component, not a live control.
2. **Nothing depended on it.** No installer step, audit unit, or command
   references it outside the repository's own files and CI. The only host-side
   footprint is the install tree described below.

**One shared credential was found and must survive this change.** The
service's `codex-api-key` is byte-identical (modulo a trailing newline) to
`~/.config/pr-agent/openai-key` and
`~/.config/aiops-diagnostics/keys/deepseek-local.key` — the same relay key used
by three separate consumers. It is not review-sentinel's credential to delete.

## Decision

Review Sentinel is retired from the server.

Concretely, in this repository:

- `review-sentinel/` is deleted in full: the service package, its tests, the
  installer, the systemd unit, the GitHub App manifest, and its README.
- The policy document's self-hosted-implementation bullet is removed. The
  review architecture keeps its two layers — Devin Review for automatic
  pull-request review, CI/Ruleset as the only mandatory gate — which is already
  what the documents assert; this change does not alter the layer count.
- Both agent-facing documents drop their `review-sentinel/` sentences.
- The CI steps that ran the removed unit tests and installer test are removed
  with them.
- `tests/test-ai-review-policy.py` loses its `review-sentinel` assertions along
  with the whole `test_review_sentinel_is_review_only_and_least_privilege` test,
  which only read the files being deleted.

On the host, as a separate, explicitly authorized cleanup:

- The user unit is removed and the install tree archived
  (`~/.config/review-sentinel`, `~/.local/lib/review-sentinel`,
  `~/.local/share/review-sentinel`, `~/.local/state/review-sentinel`).
- The shared relay key is **preserved**, for the reason recorded above.

Reintroducing a self-hosted review layer is a **separate decision that has to
bring its own acceptance evidence**. It is not a restore of this tree.

## Consequences

- The governance repository no longer ships a reference implementation of a
  review backend. The policy's description of the *allowed* shape of such a
  backend stays where it is; only the concrete implementation is gone. A future
  implementation starts from the policy, not from this tree.
- The repository shrinks by a service tree and its two CI steps, so CI gets
  marginally faster and one fail-closed assertion set disappears. The remaining
  assertions — the two-layer count, the retired-local-reviewer read-back block,
  and the CodeRabbit preservation test — are untouched and still bind.
- The GitHub App `ranlei-code-review-app-2026` cannot be deleted through the
  REST API: GitHub exposes no endpoint for it, and an App cannot delete itself
  (`DELETE /app` returns 404). It has zero installations, so it holds no access
  anywhere. Its removal is a manual owner action in the GitHub UI and is
  recorded as a pending step rather than being silently left undone.

## Supersedes

`docs/devin-review-migration.plan.md` Phase 2 item 3, which decided that
`review-sentinel`'s "files and tests stay in place; deleting them is a separate
decision." That decision is now taken. The plan document records what the
migration decided at the time; this ADR records what replaced it, in the same
way ADR 0006 superseded that plan's item 4.
