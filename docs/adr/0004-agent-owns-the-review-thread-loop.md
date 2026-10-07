---
status: accepted
---

# The Responsible Agent Owns the Review Thread Loop

`docs/adr/0003-devin-review-as-sole-first-pass-reviewer.md` left one class of
review thread to a human. Devin Review resolves the threads it considers
addressed, but only when a re-review is requested, and the policy said the rest
— a finding triaged "not applicable", a false positive, an accepted risk —
"is answered in the thread and resolved by a human."

That rule was enforced by nothing, which is the failure mode the policy already
names for itself: "A rule in this section without a check is still binding, but
nothing will stop a violation, so the operator is the control." The operator
was, in practice, the only thing closing those threads, and the observed result
was that agent runs ended with open threads they could not close. On this
repository, `#46`, `#47` and `#48` were answered and resolved by hand, and the
four threads on `#44` were each resolved by hand. A delivery that cannot finish
its own review loop is not autonomous, and the human's attention was being
spent on approving threads the agent had already reasoned about.

## Decision

The responsible agent owns the review loop end to end. Devin Review remains the
first-pass reviewer and the Ruleset still requires conversation resolution; what
changes is who satisfies that gate. The agent answers every residual thread with
a recorded disposition — fixed, accepted risk, false positive, or not applicable
— resolves the threads it has answered, and repeats the re-review until no new
finding and no unanswered thread remain. Human triage does not disappear: it
becomes an after-the-fact audit of the recorded dispositions rather than a
per-thread approving click.

The precondition is mechanical, not a convention. `bin/dev-pr-review` is the
loop in one tool: `status` lists the open threads and whether the account running
it has replied, `reply` records a disposition in-thread, `resolve` refuses a
thread that carries no reply from the account running it, and `close-loop`
resolves the answered threads and requests exactly one re-review. A thread
cannot be silently dropped, because the disposition is the thing that unlocks the
resolve, and the disposition is visible on the pull request where any operator
with write access can read it.

Nothing else about the layer moves. `Devin Review`'s own status check stays
non-required, so a Cognition outage still costs no merge availability; any user
with write access can still resolve a thread, so the reviewer cannot hold a
branch hostage; CI and the Ruleset remain the only mandatory merge gates; and AI
findings are still candidates, not verdicts. The loop terminating is a property
of the design rather than of the agent's patience: `close-loop` requests a
re-review only when that pass actually resolved something, so a re-review that
opens no new thread leaves nothing for the next pass to do.

## Consequences

The two governance mirrors, `acceptance.feature`, and the fail-closed test that
pins their wording change together, and `bin/dev-pr-review` is now part of the
release unit the installer deploys. The new failure mode is resolving a thread
without reading it, which is exactly what the old human gate prevented; it is
mitigated by the recorded disposition (a resolution with no reasoning behind it
is auditable), by the reply-before-resolve precondition, and by the operator's
audit, rather than by assuming the agent is diligent. A disposition that is
wrong is now visible after the merge instead of before it, which is a real cost
and the reason the audit is stated as part of the rule rather than as advice.

Merging stays gated on the current task's authorization. Clearing the threads
makes the pull request *mergeable*; it does not authorize the merge, and the
policy's rule that commit, push, open, and merge actions require the task's
scope is unchanged.
