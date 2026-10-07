---
status: accepted
---

# Bounded always-on policy excerpt

## Context

Every Claude Code session loads the global instruction file and warns when a
single file passes a per-file size; every Codex session loads the global Codex
file and silently truncates past its own bound. The canonical consensus policy
was 50,142 characters and was published verbatim into both places — and,
through the installer, into `~/Projects/CLAUDE.md` and `~/Projects/AGENTS.md`,
which are ancestor instruction files for every session started below
`~/Projects`. The same oversized text therefore reached each session through
several always-on paths at once.

The bound is not one number. It is computed per loader, and the two loaders
disagree: Claude Code warns above roughly 40,000 characters, while Codex's
packaged default is 32,768 bytes. A single mirror cannot satisfy one reader by
being small and the other by being complete, which is what made "just trim the
file to 39 KB" wrong on the Codex side even where it worked on the Claude side.

## Decision

The canonical policy keeps the full text. Instruction files that are loaded
into every session carry only an **always-on excerpt**, cut at an explicit gate
— the `## Mandatory Git Workflow` heading. The excerpt is the identity, host,
repository-class, files/runtimes, workspace-layout, and standards sections; the
delivery and review sections stay out of the always-on copy and remain binding
through the full text.

Three places publish that excerpt: the installer writes the user-global agent
files, and the privileged sync writes the same three root-owned mirrors. Both
derive the excerpt from the same gate in the canonical source rather than
keeping their own copy of the boundary, and the workspace top level becomes a
pointer to the full policy instead of a duplicate of it.

The `/etc/agent-governance/…` mirror keeps the full canonical text. It is never
loaded by a model — it exists for auditors — so bounding it would remove
information and buy nothing.

## Consequences

A mirror that no longer matches the canonical excerpt, or that exceeds its
loader's bound, is a check the policy audit can run instead of a thing the
operator discovers from a warning at session start. The audit holds the
user-writable mirrors to a hard failure and reports a drifted root-maintained
mirror as a warning, because the audit cannot repair a file outside its write
boundary and `sync-privileged-policy` is what brings that one back.

The excerpt boundary is now a placement rule with one ledger: sections must be
ordered so that the always-on half stays coherent, and a new always-on section
moves the cut rather than silently growing past it. The delivery sections are
read less often by a model that never opens the full file, which is a real cost;
the pointer text in every mirror and the audit's drift check are what keep the
full text one action away rather than forgotten.

The two loaders' bounds are read from the shipped binaries, not from public
documentation, so they are stated as the numbers this host observes rather than
as a contract. A loader that changes its bound changes the excerpt size the
audit enforces, and the audit is where that shows up.
