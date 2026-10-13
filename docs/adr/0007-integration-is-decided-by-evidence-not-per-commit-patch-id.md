---
status: accepted
---

# Integration is decided by evidence, not by per-commit patch-id

## What was measured

A merged task branch was reported as an orphan and could never be retired.
`chore/runner-to-self-hosted` in `health-flow` was squash-merged as PR #227, then its
change was reverted by PR #243. The daily audit reported it as:

```
WARN repo=/home/claude/Projects/health-flow branch=chore/runner-to-self-hosted state=upstream_gone
```

`dev-worktree retire` refused it for the same reason. Measured on the branch:

| object | patch-id |
| --- | --- |
| the branch's **net diff** (`merge-base..head`) | `1a33ae77…` |
| the squash commit `4a7d767` on the default branch | **the same** `1a33ae77…` |
| each of the branch's 4 **individual** commits | `7dc2c35e…`, `e594ea1a…`, `37be8f…`, `56823b91…` |

The net diff and the squash commit are byte-for-byte the same change, but **no single
commit's patch-id equals it**. Two independent defects followed.

**One: `git cherry` judges the wrong granularity.** It compares each commit's patch-id
against upstream. A squash merge collapses N commits into one commit with a **new**
patch-id, so every per-commit patch-id is absent from the default branch and `git
cherry` prints all `+`. The branch is integrated; `git cherry` cannot say so, and it
never could -- this is how squash merging works, not an edge case. Measured: the same
`git cherry` output on a branch whose commits *are* an ancestor returns all `-`.

**Two: the cheapest signal pre-empted the strongest.** `dev-policy-audit`'s
stale-branch scan checked `upstream:track` first and `continue`d on `[gone]`, never
asking whether the branch was integrated. Deleting the remote branch on merge is the
normal GitHub outcome, so "merged and deleted" -- the most common case -- always
reported as an orphan and was never eligible for retirement.

The evidence that the branch *was* integrated already existed and was already
trusted elsewhere: `gh pr list --head` reports PR #227 with `headRefOid` equal to the
branch head and a merge commit (`4a7d767`) that is an ancestor of `origin/main`.
`dev-worktree retire` even consulted this via `branch_has_verified_merged_pr`; the
daily audit did not.

This is not one branch. The same audit output carried `integrated_not_retired` for
`health-flow`'s `chore/afk-1.7.19` and afk-bootstrap's `chore/1.7.19-all-live-prompts`,
all squash-merged.

## Decision

Integration is decided by **the strongest available evidence**, in one place, by one
predicate: `branch_integration_route` in `lib/dev-git-common.sh`. It answers with the
**route** that matched, because `dev-worktree retire` reports *how* a branch was
verified (`verification=git` vs `verification=pr#N`) and a boolean would erase that.

Routes, in order:

1. **ancestor** -- `merge-base --is-ancestor`. A merge commit, a fast-forward, or work
   rebased onto the default.
2. **cherry** -- every commit's patch is already upstream under another hash
   (cherry-pick / rebase). The count of `+` lines is computed explicitly and only the
   exact integer `0` counts; a failed `grep` (exit >1) yields an empty string and thus
   **falls through** instead of being read as "no `+`, therefore integrated". The old
   `! grep -q '^+'` had exactly that false-positive: a broken `grep` looked like a
   successful match of "nothing".
3. **pr#N** -- this branch's head has a **merged** pull request whose merge commit is
   an ancestor of the default. This is the only route that sees a squash merge. It needs
   `gh` and is skipped when `gh` is unavailable; because route 3 was never consulted by
   the daily audit before, skipping it is exactly the old behavior, never worse.

It is parameterized by repository (`git -C`), because the daily audit walks many
repositories and the working directory is not the one under test.

`dev-policy-audit` **asks integration first, then upstream state**: an integrated
branch reports `integrated_not_retired` whether or not its remote is gone, and only a
genuinely unintegrated branch with a deleted remote reports `upstream_gone`. The state
is chosen by the strongest evidence rather than by which signal is cheapest to read.

An **empty** branch (`head == recorded base`) is the caller's `empty` case and is
decided before the predicate: an empty commit has an empty patch-id, so `git cherry`
marks it `+` and it is never mistaken for integrated.

## Consequences

- A squash-merged branch is now reported `integrated_not_retired` and is eligible for
  `dev-worktree retire`, restoring the "delete the agent-owned task branch after merge"
  invariant that squash merging had been silently defeating.
- The daily audit may call `gh` for branches the pure git routes cannot classify. When
  `gh` is absent or unauthenticated it degrades to the git routes -- the prior behavior.
- The predicate lives in the shared library, so the two tools that decide integration
  (`dev-worktree`, `dev-policy-audit`) cannot drift; only `dev-worktree`'s retire layer
  narrows it to the git routes, because it must distinguish a `git` merge from a `pr`
  merge in its output.
- No branch is deleted automatically on a `1` (undecidable) answer; the audit reports
  and retirement stays a separate, deliberate step.

## Rejected alternatives

- **A pure-git squash detector** (net-diff patch-id equals some commit's patch-id on the
  default branch). Best-effort only: it holds when the branch was cut from the squash's
  parent, but once the default branch advances past that point the diff context differs
  and the patch-id diverges -- it would silently miss exactly the cases this change
  exists to catch. The merged-PR route is authority- and operation-independent.
- **Widening the audit's tolerance** (accepting `[gone]` branches as "probably merged").
  That is the false-positive the audit exists to prevent: it would mark *unmerged*
  abandoned work as safe to delete.
- **Making `gh` mandatory for the audit.** It would make the daily audit fail or hang on
  a machine without network or credentials. The route is an addition, not a dependency.
- **Folding the merged-PR route into `branch_has_integrated_commits`.** That function's
  name and contract are about *commits*; a squash merge leaves no commit of the branch
  upstream. Keeping it git-only is what lets `retire` still report a `git` verification
  distinctly from a `pr` one.
