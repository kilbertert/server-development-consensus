---
status: accepted
---

# Devin Review as the Sole First-Pass PR Reviewer

The server's three-layer AI review architecture named the self-hosted PR-Agent
GitHub App as the automatic PR advisory reviewer. On 2026-09-21 that layer was
measured rather than assumed: the `pr-agent.service` unit had been active for
four days and its webhook endpoint answered `POST /api/v1/github_webhooks 200`,
but over the preceding 30 days it logged 58 automatic `/review` attempts, 50
hard failures (`Failed to generate prediction with any model of
['openai/glm-latest', 'openai/glm-flash-free']`), 108 `litellm.InternalServerError`
and 104 `litellm.BadGatewayError` events, and no successful publication record.
The GitHub side agreed: none of the four most recent `AI-Ops` pull requests
carried a PR-Agent comment. The layer had been dead for a month and its failure
was silent by construction, so the policy text describing it described
something that was not happening.

At the same time a second reviewer was already active and unrecorded. CodeRabbit
(`coderabbitai[bot]`) had reviewed every recent pull request on the enrolled
repositories, locked in by eleven checked-in `.coderabbit.yaml` files and a test
assertion. Devin Review, connected through the Devin.ai GitHub App, produced its
first review on `kilbertert/AI-Ops#345` on the same day.

## Decision

Devin Review becomes the server's sole first-pass PR reviewer. PR-Agent is
retired rather than repaired: its only remaining differentiator was that source
code stayed inside the development plane, and the owner has directed that
repositories be published, which removes that boundary deliberately rather than
by accident. CodeRabbit is stood down on the enrolled repositories so that
exactly one reviewer holds the slot, because two reviewers on one pull request
double the triage cost without widening coverage. It is removed there by
dropping those repositories from the GitHub App installation (one reversible
act) while every configuration file stays in place; the remaining repositories
keep it until they are enrolled. The comparison checkpoint that once gated that
handover was dropped on `2026-09-21`, when the operator settled the question by
reading both reviewers' output directly instead of counting it.

`sports-ability` is outside the enrolled set. It stays private, so the
open-source tier does not apply to it, and enrolling it would send minors'
sports and genetic data, a live relay credential and client identifiers to a
third party. It keeps CodeRabbit until it clears the publication preconditions
or is reviewed manually.

Repository publication is a recorded decision, not a side effect of the tool
choice. Every repository may be published, but publication is gated on a
per-repository precondition check: third-party personal data and live
credentials are removed from the working tree and from history, and any exposed
credential is rotated, before the visibility flag changes. A repository that
cannot clear that check stays private and is simply not enrolled in Devin
Review.

Repositories are enrolled for review by observed pull-request traffic, not by
inventory size. Review budgets stay advisory: Devin Review findings are
candidates, CI and the Ruleset remain the only mandatory merge gates, and the
per-PR spend limit caps automated review spend. Auto-fix is enabled, with
`devin-ai-integration[bot]` as the only allowlisted bot, so a fix commit may
arrive on the task branch and the responsible agent rebases on it rather than
rewriting it.

## Consequences

The policy's named layer, the two governance documents that repeat it, and the
test that asserts that wording must change together; the test is
fail-closed, so the documentation cannot drift from the architecture without CI
failing. Review now depends on a third-party service on the service plane
rather than a self-hosted loopback process, so a Cognition outage, an account
problem, or a pricing change is an availability and cost dependency the server
did not previously carry; the per-PR spend limit and the manual `/devin review`
path are the mitigations. Going public unlocks repository Rulesets, which
GitHub Free cannot enable for private repositories, closing a gap that the
policy already required and that is currently unmet on every repository.

Both retired reviewers are disabled rather than deleted: the PR-Agent unit,
its virtualenv and its credential directory stay on disk, and the CodeRabbit
configuration files stay in their repositories until the replacement has run on
real pull requests. Removal is a separate decision made after the replacement
is observed working.
