# Server Development Consensus

This is the non-negotiable development policy for this server. It applies to
all projects, interactive shells, Codex sessions, Claude Code sessions, and
other agent tools. Project instructions may add stricter rules but must not
weaken this policy.

## Account Boundary

- `claude` is the only interactive development account and owns developer
  tools, project source, caches, user services, and AI-tool configuration.
- `root` is for explicit host maintenance only: packages, system services,
  Docker daemon administration, Nginx, SSH, accounts, and recovery. Never
  develop, run AI tools, start project applications, or store source in
  `/root`.
- `ranlei` is a locked, non-login service identity for `/opt/ranlei-blog`. Do
  not use it for development or change the account without an explicit service
  migration.

## Host Fleet And Multi-Host Development

The fleet is not a single machine. Every host that an agent may reach, deploy
to, or reason about has exactly one declared role, one owner, and one
documented access path. The role model and its rules live in this policy; the
concrete inventory (addresses, access methods, and where credentials are kept)
is internal operating record and stays in the private operations record, never
in this public repository.

Host roles:

- **development host** — the interactive host this policy describes:
  `/home/claude/Projects`, the `claude` account, `systemctl --user` units, and
  the development port registry. One active development host is the norm; a
  second one is a deliberate split of work, not an accident of convenience.
- **project production host** — runs the deployable service of exactly one
  project for real users. It is not a development environment, and it does not
  carry a second project's work without an explicit decision.
- **service host** — carries the deployable services of more than one project
  for real users, each isolated from the others under its own project-scoped
  service identity. It is the role a host takes when the operator's direction
  is that services live on service hosts and the development host develops. A
  host that gains a second project changes role from `project production host`
  to `service host`; that change is recorded, never drifted into.
- **shared service host** — backs one or more projects with a database, queue,
  proxy, or comparable dependency.
- **runner host** — hosts CI runners and deployment working directories.

`project production host` and `service host` are both **service hosts**: they
serve real users rather than develop, and every rule below that says "service
host" applies to both.

Rules:

- A host joins the fleet through an explicit, recorded decision that names its
  role, owner, purpose, and lifecycle, and that adds it to the private
  operations inventory. A host without a declared role is not covered by this
  policy, and agent work is not allowed on it.
- **The development host carries no service reachable from outside the
  development plane.** It terminates no public entry point, and it binds no
  non-loopback address in order to serve a real user. A service found doing so
  is debt to be worked off under the migration rules below, not an exception to
  this one. This is what makes the two kinds of host mutually exclusive rather
  than merely different in emphasis.
- Service hosts are deployed to, not developed on: no source checkout under a
  user workspace, no interactive agent session, no editing of running code.
  Changes reach them only as an artifact built from a merged revision of the
  protected default branch.
- **A service identity has the scope of one project** — not one process, and
  not the whole host. A project's processes share one identity; two projects
  never do. The identity is a system account with no login shell, no password,
  no sudo, and no shared group membership, with a home under that project's
  service root; it runs the project's processes under the host's service
  manager, never as the interactive development account and never as an
  unmanaged foreground process. Sharing one identity across projects makes
  every credential file that ownership and mode protect readable by every
  service on the host, so a single defect in one project yields every other
  project's production credentials with no privilege escalation and no lateral
  movement. A host's service identity count therefore follows its project
  count.
- Internal service ports on a service host bind to loopback and are declared
  with that host's role. Each host owns the registry of the fixed ports it
  allocates, and those pools are disjoint: a port number means the same thing on
  every host, and no two hosts can silently collide. The development port
  registry governs the development host, not the fleet. A port inherited from a
  host being migrated away from may be kept as a recorded exception; a new
  service never copies such an exception.
- Only a service's public entry point may bind a non-loopback address. Each
  such exposure — firewall rule, cloud security group, reverse proxy, TLS
  termination — is an explicit security decision recorded with the host.
- **Changing an exposure is decided from observed traffic, never from which
  ports are listening.** A service bound to a non-loopback address is not proof
  that anything uses it, and a service with nothing listening is not proof that
  it is dead: an on-demand service behind a permanent entry point looks exactly
  like an abandoned one. Before an exposure is closed, an entry point is moved,
  or a service is retired, its actual use is observed and the observation is
  recorded. Where observing it is not possible, the service is treated as in
  use.
- **Every host belongs to exactly one trust plane.** The *development plane* is
  a private overlay carrying machine-to-machine access between the development
  host and the hosts that run agent or CI work; joining it is a recorded
  decision, not something fleet membership implies. The *service plane* is
  public SSH with public key authentication only, with the cloud firewall
  restricted to known sources. A service host does not join the development
  plane, because that would make production reachability depend on a
  third-party control plane and a personal account. Password authentication is
  disabled on every host, and every management interface binds loopback or the
  private plane.
- **The governance release unit is installed where agents and review run.** It
  is installed on the development host and on runner hosts that adjudicate
  review; a service host receives only its projects' deployment artifacts.
  Installing rules that constrain agent sessions on a host that runs no agent
  session adds attack surface without adding control.
- **Migration is a contract, not an improvisation.** A service moves to a
  service host only when all of these hold: its deployment assets are versioned
  in the project repository; it has an executable acceptance check whose result
  is recorded with the build identity, environment, and timestamp; the previous
  deployment keeps running until the new one passes that check; and switching
  traffic and retiring the previous instance are two separate steps, so the
  rollback path is never lost in the step that proves the new path. Moving a
  public entry point is one deliberate, canaried change, never a side effect of
  moving a service.
- **Migration is triggered by work, not by a schedule.** A new service is
  deployed to a service host directly; an existing service moves when it is
  next changed. The first batch is the set of services that bind a non-loopback
  address with no tunnel in front of them: they have neither a reason to be on
  the development host nor a recorded exposure decision. No batch table is kept
  after that, because a list that is not derived from a criterion goes stale.
- **Access material lives in one encrypted inventory held outside version
  control**, encrypted to a key the operator alone holds. It records hosts,
  roles, owners, access paths, data-source pointers, entry-point secrets, and,
  for each project, where its environment file lives; it holds secrets
  themselves only where no indirection is possible. The map of the fleet is not
  published alongside the rules for it. Plaintext credentials are migrated
  entry by entry as the service they belong to is touched, never in one sweep
  that breaks every dependent at once.
- **CI runners are part of the development host role and stay there.** Runners
  are consumers of the development flow, not user-facing services, and a
  service host's restricted egress makes it a poor runner host. Converting them
  to one-job-per-runner instances is deferred.
- Until a new service host passes the project's acceptance checks, the
  previous host and the previous deployment stay available as the rollback
  path. A migration never makes the old host unrecoverable in the same step.
- Changing a host's role, moving a public entry point, and retiring a host are
  deliberate changes: they carry the same evidence and review requirements as a
  code change and are never the side effect of a deployment command.

- **A host's role is recorded in exactly one machine-readable place.** The
  concrete inventory lives, as always, in the private operations record; what
  this rule adds is that it is machine-readable rather than prose, so that a
  tool can answer "which host am I on and what may it do" without a human
  reading a table. Two records naming the same host's role is the failure this
  avoids: they drift, and a reader cannot tell which one is current. The
  narrative half of a private record — exposure inventories, ingress chains,
  change and rollback ledgers, credentials locations — stays prose, because a
  machine-readable file cannot carry the reasoning that makes those useful.

- **A project declares which hosts it reaches, and that declaration is
  reviewed.** The declaration names targets by logical name and carries the
  paths that matter; addresses, fingerprints, and credentials stay in the
  private record. The split is what lets the declaration live in the project
  repository — reviewed in the same pull request as the change that needs it —
  without publishing a map of the fleet. A project whose repository another
  organization governs keeps both halves outside version control.

- **Reaching a host is a fixed operation, not a fresh script.** The form — how
  to run a command, read a file, copy an artifact — is uniform across hosts;
  only what happens after arrival belongs to the project. This is what the
  declaration buys: the three things `ssh` config cannot answer — what a host
  is, where things belong on it, and what success looks like — become readable
  instead of being re-derived by hand each time.

- **Identity is asserted before anything reaches a host.** A host whose key
  does not match its record is unreachable, not merely suspect. A host absent
  from the record is unreachable as well: an unrecorded machine is not
  guessed at. This is the same fail-closed shape as an unreadable repository
  class, and it is the rule that turns "I deployed to the wrong machine" from
  a thing discovered afterwards into a thing that could not happen.

- **Reaching a service host is not the same as changing one.** Running a
  command or writing a file on a host that serves users is gated: the written
  artifact must be identified, and reading is unrestricted. A tool that makes
  hand-editing production convenient erodes this section rather than serving
  it. The gate's purpose is to make the discouraged path require a deliberate
  act, not to make it impossible — the rule it enforces is the one above,
  that changes reach service hosts as artifacts built from a merged revision.

**Enforcement.** Most of this section is a convention: it is enforced by
review, not by automation. The checks that do exist — port registry presence
and integrity, workspace and worktree lifecycle, the installer's managed
copies, and the managed Git hooks — are the only rules here that fail on their
own. A rule in this section without a check is still binding, but nothing will
stop a violation, so the operator is the control. Treating a convention as
automation is the failure this paragraph exists to prevent.

## Repository Classes

This policy describes how work is delivered *on this host*. It applies in full
only to repositories whose delivery process this host owns; a repository whose
process belongs to another organization keeps its own rules. Every repository
in the workspace has exactly one class:

- **server-managed repository** — the default class. The host workspace owns
  the task branch, the pull request, deterministic CI, and the protected
  default branch, so every rule in this policy applies.
- **externally governed repository** — a repository whose review, merge, and
  release process another organization owns. The host owner classifies it when
  it enters the workspace and records the classification, with its owning
  organization and purpose, in the private operations inventory. The
  classification is a local marker on that checkout; it is never committed and
  never travels with the repository.

An externally governed repository is exempt from the rules that describe how
*this host* delivers code:

- the protected-default-branch local guard, the task-branch workflow, and the
  pull-request gate;
- the Conventional Commits contract and the commit-time default-branch policy;
- the server task lifecycle commands and the delivery bookkeeping they record;
- the server-side audit of that repository's delivery branches and worktrees.

The host stops maintaining its own delivery metadata in an externally governed
repository, but it does not rewrite what is already present. Those keys can
still point at the repository's own hook chain or at a paused worktree, and
erasing them would break a process this host does not own.

Exemption is not a security boundary moving. Everything that describes *this
host*, *this account*, and *this workspace* still applies to every repository
regardless of class, and is never waived by the class marker:

- the account boundary and secret isolation;
- workspace layout, including where a task worktree may live;
- the development port registry and the listener and exposure rules;
- the host fleet rules and every rule about changing host state.

The class decides scope, not priority. It cannot exempt a server-managed
repository from a security invariant, cannot relax the account boundary, and
cannot reclassify work that this host is already delivering. Nor does it make
another organization's process subordinate: an outside review process is a
reason to be more careful, not less. This host must not overwrite, weaken,
silently repair, or take over a process it does not own, and it must not read
its own delivery metadata into a repository it does not own.

The AFK compatibility contract and the invariants it publishes describe
server-managed repositories. Classifying a repository is a scope declaration
made by the host owner, never a structured exception chosen by a project:
an unknown or unreadable class is treated as server-managed, so an exemption
can never widen by accident. Changing a repository's class carries the same
recorded decision, evidence, and review requirements as changing a host role.

## Files And Runtimes

- This section describes the development host. A project production host
  uses the service layout declared with that project, under the fleet rules
  in `Host Fleet And Multi-Host Development`.
- Create and maintain projects only below `/home/claude/Projects`.
- `/home/ranlei/Project` and related `/home/ranlei/*` paths are compatibility
  symlinks. Do not create new work there, replace them, or remove them until
  live service and Docker references have been explicitly migrated.
- User AI tools, Conda, caches, VS Code Server, and user configuration belong
  below `/home/claude`. System Node under `/usr/local` is root-maintained.
- The policy, Codex instructions, common library, commands, managed hooks,
  audit units, and configuration are one release unit. Deploy them only through
  the canonical installer. If installation rolls back, fix the blocker and
  rerun it; never project an individual policy or tool file manually.
- Keep new developer-owned files private by default (`umask 027`). Do not use
  ACLs, cross-user groups, or recursive cross-account ownership changes as a
  shortcut.

## Workspace Layout

The projects workspace is a curated area, and its top level stays
predictable so that people and agents can tell active work from history at
a glance.

- The top level of `/home/claude/Projects` may contain only: canonical
  checkouts of active projects named after their origin repository; policy
  and index files maintained by the canonical installer (AGENTS.md,
  CLAUDE.md, SERVER-DEVELOPMENT-CONSENSUS.md, DEVELOPMENT-PORT-REGISTRY.md,
  WORKSPACE.md, INDEX.md); and underscore-prefixed functional directories
  (`_archive/`, `_runners/`).
- Task worktrees are created with `dev-worktree start`. Its default
  location is the managed central area `/home/claude/Projects/.worktrees/`;
  an explicitly given path is honored only inside a repository checkout,
  where the worktree must be gitignored. Linked worktrees must never appear
  as visible top-level entries: `dev-worktree start` rejects them, and
  `dev-worktree audit` plus the daily policy audit report them as
  violations.
- Projects follow a restore-then-work archive flow: a project idle for
  more than 30 days with no service references moves to
  `_archive/<year>/`; before work resumes it moves back to the top level
  or is re-cloned from its origin, and development never happens inside
  `_archive/`.
- Deployment artifacts (self-hosted runner working directories, standby or
  deploy checkouts) are not top-level projects. They live under
  `_runners/` or another dedicated, service-managed location and are
  referenced by their systemd units; existing top-level deploy checkouts
  migrate there as part of that service migration.

## Standards-Based Engineering

- Before defining or changing a public contract, protocol, schema, diagnostic
  taxonomy, logging or telemetry model, security boundary, persistence
  guarantee, time or locale behavior, or cross-system interface, check for an
  applicable authoritative standard or official platform specification.
- Prefer, in order: formal standards and official specifications, official
  dependency documentation, verified repository conventions, established de
  facto standards, then a documented local design.
- When a standard materially affects observable behavior, record its scope and
  concrete mapping, and verify the implementation with focused tests.
- Do not use "best practice" to justify speculative abstractions, dependencies,
  or complexity. When no applicable standard exists, follow established
  repository conventions and document important tradeoffs.
- Routine local naming and implementation details do not require external
  research unless ambiguity or interoperability risk makes it useful.

## Mandatory Git Workflow

The default branch (`main`, `master`, or the remote's configured default) is a
protected integration branch. It must represent reviewed, tested, deployable
code. Normal development never happens directly on it.

For every code, configuration, schema, infrastructure-as-code, or maintained
documentation change:

1. Establish the repository's canonical checkout before editing. Fetch with
   pruning, inspect every worktree and branch, and update the default branch
   using fast-forward only. A task worktree is not the canonical checkout
   unless that handoff path is explicitly recorded.
2. Create one short-lived branch for one logical task before editing tracked
   files. Use `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/`, or
   `hotfix/`, followed by a short lowercase kebab-case description. Agent-owned
   branches may use their established prefix, such as `codex/`.
3. Make focused commits. Each commit should leave the branch coherent; use the
   project's commit convention, or clear Conventional Commit style when none
   exists. Commit messages must use Conventional Commits
   (`<type>(<scope>): <subject>`, types `feat fix docs style refactor perf test
   chore build ci revert`, with an optional `!` for breaking changes and an
   optional scope). The managed `commit-msg` hook enforces this format at commit
   time; it is fail-closed, and a repository that opts out must set
   `serverPolicy.commitMessageOverride=default-branch-only` explicitly. Keep
   each commit small and focused; as a guardrail, a single commit is normally
   under 300 changed lines and a PR under 500-800 lines. Never commit secrets,
   local credentials, `.env` contents, or unrelated generated artifacts.
4. Run the repository's formatter, static checks, tests, and build in
   proportion to the change. Add or update tests for regressions and non-trivial
   behavior. Record any check that cannot be run.
5. Push the task branch and open one pull request. Multiple commits and pushes
   belong to that same branch and PR; each push reruns deterministic CI, not an
   unbounded AI review. Do not create a new PR for every commit.
6. Keep the PR focused, describe the behavior and verification, and resolve
   review threads. Use a lightweight PR template (`changes`, `tests`, `checklist`
   sections, with an issue/`#123` reference when applicable) when a repository
   provides one; otherwise describe the change, its verification, and its scope
   in the PR body. A PR is normally under 500-800 lines. All required
   deterministic CI checks must complete successfully. AI review is advisory by
   default: verified findings must be fixed, while false positives, findings
   outside the agreed threat model, and accepted risks require explicit human
   triage rather than repeated model runs.
7. Merge through the Git hosting service after the branch is current and every
   required check passes. Prefer squash merge unless project history requires a
   different method. After the hosting service confirms the merge, fetch with
   pruning, verify the merge commit and changed paths on `origin/main`, fast-
   forward the local default branch, and only then delete agent-owned task
   branches and worktrees.

8. When a repository publishes versions, use Semantic Versioning
   (`MAJOR.MINOR.PATCH`; a `!` breaking change or incompatible API bumps MAJOR,
   a backward-compatible feature bumps MINOR, a backward-compatible fix bumps
   PATCH). Create annotated tags (`git tag -a`) on the merged default branch and
   push them separately. Releases are a deliberate, authorized act: a repository
   should agree its versioning contract and release cadence before tagging
   begins.

Direct pushes, force pushes, local merges pushed to the default branch, and
using `--no-verify` to bypass the server guard are prohibited. Do not weaken or
disable a GitHub Ruleset, required deterministic check, or Git hook to make a
change pass. AI review workflows may be paused or reconfigured through an
explicit governance decision when their cost, latency, or false-positive rate
is disproportionate; that is not a CI bypass.

If existing uncommitted work is found on a default branch, preserve it by
creating a task branch in place before continuing. Never discard it merely to
make the worktree clean. Read-only investigation and analysis tasks do not
require a branch.

## Git And Worktree Delivery Invariants

The repository root used for handoff is a delivery surface, not an incidental
checkout. Every maintained repository must have one declared canonical path
and one declared default branch. Agents must report the canonical path, current
branch, `git status --short --branch`, `git worktree list`, and `git branch -vv`
before editing and before final handoff.

Use `dev-worktree start TYPE DESCRIPTION [PATH]` for a new isolated task
worktree. It creates the branch from the fetched `origin/<default>` with no
upstream to the default branch and records its base, owner, path, and lifecycle
state. Run `dev-worktree audit` before handoff and `dev-worktree retire PATH`
only after integration is verified. `retire` refuses dirty or unintegrated
work; it never deletes a remote branch. A user-owned or intentionally paused
dirty worktree may be registered with `dev-worktree preserve PATH REASON` and
reactivated with `dev-worktree activate PATH`.

- Create agent-owned worktrees from `origin/<default>` (not from a stale local
  task branch) and record the task branch, worktree path, base commit, PR
  number, and owner. Never silently repurpose a user's existing worktree.
- Before opening or merging a PR, fetch with pruning and verify that the task
  branch contains the current base (`git merge-base --is-ancestor
  origin/<default> HEAD`). If the base moved, update the task branch and rerun
  deterministic CI before merging. Do not use force-push or rewrite a
  published task branch merely to resolve drift.
- A branch whose upstream is marked `[gone]`, or a worktree whose branch is no
  longer present on the hosting service, is a stale-delivery state. It must be
  reported and must not be presented as the current integrated project.
- The pre-push guard rejects a task branch when its committed paths overlap
  uncommitted paths in another worktree of the same repository. Resolve,
  commit, or explicitly preserve the other worktree before delivery; a
  preserve marker documents ownership but does not bypass an actual overlap.
- The daily policy audit reports and fails on task branches that track the
  default branch, gone upstreams, integrated worktrees that were not retired,
  and unpreserved worktrees whose only changes are uncommitted while the
  default branch has advanced. It reports state only and never deletes files,
  branches, or worktrees automatically.
- After merge, verify `gh pr view` reports `MERGED`, capture the hosting merge
  commit, confirm every changed maintained path exists at `origin/<default>`
  with `git show`, and fast-forward the local default branch. For documentation
  changes, verify the final path and links from the canonical checkout.
- Delete only agent-owned task branches and worktrees after the checks above.
  Preserve user-owned worktrees, uncommitted changes, and compatibility paths.
  Remote branch deletion, local branch deletion, and worktree removal are
  separate operations and must each be reported.
- If `gh pr merge` selects a local merge path because the default branch is
  checked out in another worktree, do not move or reset that worktree. After
  the merge gates pass, use the hosting service's merge API or UI, then run the
  same post-merge verification.
- The final handoff must include `base_sha`, task branch, PR URL, merge commit,
  final `origin/<default>` SHA, deterministic check results, changed-path
  verification, and the exact worktrees/branches that were cleaned up.

## Acceptance And System-Test Evidence

- For a user-visible, API, schema, persistence, permission, or cross-system
  change, the task must define an acceptance contract before implementation.
  Store it with the change as `acceptance.feature` (or the repository's
  equivalent) using Gherkin `Feature`, `Rule`, `Scenario`, `Given`, `When`, and
  `Then`. Scenarios describe observable outcomes for a user or external system;
  internal database state is not sufficient as the only `Then` assertion.
  This maps Cucumber's Gherkin semantics to server acceptance work: `Given` is
  known state, `When` is an action or event, and `Then` asserts an observable
  result. System testing verifies the integrated system against these specified
  requirements; it does not replace component or integration tests.
- The same change must include a `qa-plan.md` (or repository equivalent) when
  system-level verification is meaningful. Each case names an ID, environment,
  preconditions, test data, ordered actions, expected observable results, and
  cleanup. The plan is executable by a person or an automated UI/API runner;
  "tested manually" is not evidence.
- The implementer owns the code, unit/component tests, and executable
  acceptance steps. A separate reviewer or QA runner may execute the same
  artifacts, but agents are replaceable roles: the artifacts, results, and
  gates are the governance contract.
- Record traceability from requirement to `Feature`/`Rule`, test case, result,
  and defect. A passing result must include the commit or build identity, test
  environment, timestamp, and retained logs or report artifact. A failed or
  blocked case must name the reason; it must not be reported as passed.
- Test scope is risk-based. CRAP/complexity and coverage analysis is required
  for changed high-risk or branch-heavy code when the repository has a
  compatible tool. Mutation testing is required for core business rules,
  authorization/security, money, persistence, or regression-prone code when a
  practical tool exists. Otherwise record why it was not run and use focused
  tests or human risk acceptance. Neither metric is a universal quality score.
- These artifacts do not weaken deterministic CI, Rulesets, human review, or
  security boundaries. AI-generated specifications and findings are candidates
  until a human confirms scope and acceptance; an agent may not silently relax
  a requirement to make a test pass.

## Pull Request Gate

- Required merge gates are deterministic repository checks: tests, build,
  formatting, static analysis, migrations, and other project-specific CI.
- The server uses a three-layer code-review architecture:
  1. **OpenCodeReview CLI + delegation**: Codex or Claude runs a bounded local
     review during the development loop, preferably through delegation so the
     newly opened review context drives the inspection. It does not use a
     GitHub Action and does not depend on an OCR gateway.
  2. **Devin Review**: the server's Devin Review connection automatically
     reviews a PR when it is opened, reopened, or marked ready for review.
  3. **CI/Ruleset**: deterministic CI and the hosting service's Ruleset are the
     only mandatory quality and merge gates. AI output never becomes an
     authoritative required check.
- Each layer has one owner and a separate budget:
  - `ocr review` is the server's local development review tool. It runs as the
    `claude` user against the workspace, commit, or branch range and can be
    delegated to Codex or Claude Code. Run it with an approved local provider,
    or use its delegation mode when no provider is configured. It is advisory
    and must be run at a meaningful milestone, not after every edit or every
    agent turn. It must not invoke the GitHub Action.
  - Devin Review is the server's automatic PR advisory reviewer. It reviews the
    initial ready PR, does not rerun after every push, and never replaces
    deterministic CI or human triage. When auto-fix is enabled it may push a fix
    commit to the task branch, so the responsible agent rebases on the remote
    task branch before continuing. After a material change made in response to
    verified findings, the responsible agent requests one re-review with
    `/devin review`; the human operator is not expected to trigger it manually.
    CodeRabbit is the rollback path for this layer. It is stood down through the
    GitHub App installation rather than by deleting its configuration, so
    restoring it is a deliberate, recorded act.
  - ClawSweeper is a separate GitHub PR/issue queue and evidence reviewer. The
    OpenClaw-hosted instance is not a public service for third-party
    repositories; using it for this server requires a separately deployed and
    permission-scoped instance. Installing an App alone does not provide that
    backend. Its first deployment must use an explicit repository allowlist and
    approved model/retention boundary; workers may read only the selected
    repository and PR context, never TEAM-MEMORY, host configuration, logs, or
    credentials. A public-repository report is a redacted candidate that needs
    human approval before publication.
  - The governance repository's minimal self-hosted implementation is
    `review-sentinel/`. It is review-only, exact-head deduplicated, and
    disabled until a separately created GitHub App and a dedicated Codex home
    are configured. It must not reuse the interactive `~/.codex` home or a
    credential-embedding wrapper; its App permissions exclude contents write,
    workflows, administration, merge, push, and autofix operations. With Devin
    Review holding the automatic review layer it stays disabled rather than
    being brought into service.
- OpenCodeReview's GitHub Action is not part of the server architecture and must
  not be installed or triggered for normal development. Existing legacy action
  files are migration debt and should be removed through focused PRs. The
  `review-ready` label must not trigger OpenCodeReview.
- AI findings are review candidates, not authoritative verdicts. A human must
  confirm severity and applicability. A local OCR pass, one automatic Devin
  Review, and at most one re-review are the default budgets for a logical
  milestone; the re-review is allowed after a material change or explicit human
  request. Stop when review cost,
  latency, or noise exceeds likely value.
- Public repositories use an active Ruleset with no bypass actors, require a
  pull request, require the branch to be current, and require the selected
  deterministic CI checks.
- Private repositories on GitHub Free cannot enable Rulesets or legacy branch
  protection. The same workflow is still mandatory, and the local guard still
  prohibits direct default-branch pushes, but the hosting account must be
  upgraded before remote enforcement is equivalent.

## Agent Behavior

For a task that will edit maintained files, agents must first inspect the
worktree, current branch, default branch, remotes, and existing user changes. If
the current branch is the default branch, create a task branch before editing.
Work with existing changes and never discard them without explicit approval.

Creating a local task branch is a normal preparation step. Committing, pushing,
opening a PR, merging, releasing, or deploying remains subject to the user's
requested scope. If the task does not authorize those remote or delivery
actions, leave verified changes on the task branch and report the remaining
delivery step. Never substitute a direct default-branch push.

Before changing host-level state, inventory affected accounts, services, paths,
and live references and preserve a rollback path. After a migration, verify
ownership, account/group state, service cgroups, health endpoints, and
compatibility references. Never delete archives or compatibility paths merely
to make the filesystem appear cleaner.

## Development Review Sequence

For normal work led by Codex or Claude Code:

1. Start on a task branch and inspect the current worktree before editing.
2. For changes covered by the acceptance contract, produce or update the
   Gherkin feature and QA plan before implementation. For low-risk internal
   changes, record the reason these artifacts are not applicable.
3. Implement the smallest coherent change, add unit/component tests, make the
   acceptance scenarios executable where applicable, and run deterministic
   local checks.
4. Run risk-triggered complexity/coverage or mutation checks and retain their
   reports, or record the explicit non-applicability reason.
5. At a meaningful milestone, run `ocr review --from <default> --to <branch>`
   only when an approved local provider is configured; otherwise invoke the
   installed OpenCodeReview delegation skill. Use `--preview` first for a large
   or unfamiliar change. Do not run OCR after every turn.
6. Triage local findings once. Fix confirmed defects, record accepted risks and
   false positives, and do not turn every model suggestion into added complexity.
7. Commit, push, and open the PR. Devin Review automatically reviews the PR when
   it is opened, reopened, or ready for review; it does not rerun after every
   push.
8. The responsible agent waits for the Devin Review result, triages findings
   once, fixes verified defects, and records false positives or accepted risks.
   Auto-fix may have pushed a commit to the task branch, so fetch and rebase on
   the remote task branch before continuing; never force-push it. After a
   material change, the agent requests one re-review with `/devin review` and
   waits for it; the human operator does not manually trigger the review loop.
9. Execute the QA plan when required and attach its deterministic result
   artifact. A missing, failed, or blocked required case stops the handoff.
10. Wait for deterministic CI and merge only through the hosting service after
   all mandatory checks pass. AI review remains advisory and feedback never
   replaces tests, human judgment, or the PR gate.

## Internal Knowledge And Public Projection Boundary

- TEAM-MEMORY, agent memory, engineering notes, logs, commit streams,
  repository metadata, filesystem paths, service topology, account details,
  credentials, and other internal operating records are private by default.
- Never directly or bulk-sync raw internal records to a public service. Public
  material must be a separate artifact created through explicit selection,
  redaction, editing, and human approval before publication.
- A public projection is not an authoritative engineering record. It must not
  overwrite, approve, or otherwise mutate its internal source of truth.
- Public feedback may create an inbox candidate for later review, but it must
  never automatically modify or approve formal TEAM-MEMORY entries.
- When the sensitivity or publication authority of information is unclear,
  keep it private and request explicit direction.

## Engineering Article Publication

Engineering work may produce a public article candidate at a meaningful
milestone, but publication is never an automatic completion requirement. An
agent may recommend an article; writing to the public blog, pushing a content
branch, merging, or deploying requires explicit human authorization in the
current task.

When that authorization is present, Codex, Claude Code, and other agents use
the same Engineering Article Release workflow:

1. Build a publication brief from verified outcomes only: intended audience,
   public angle, title/slug, proven claims, acceptance boundaries, reusable
   lessons, and an explicit exclusion list.
2. Create a separately written and narrated public artifact. Never copy raw
   chats, hidden reasoning, TEAM-MEMORY bodies or evidence, logs, commit
   streams, repository metadata, filesystem paths, service topology, account
   data, private endpoints, credentials, tenant data, or identifiers into the
   article.
3. Preserve uncertainty and scope. State what was actually verified, the
   platform and scenario when relevant, and what remains unproven. Do not turn
   one canary or partial workflow into a universal product claim.
4. Leave the source project's worktree and internal records unchanged unless
   the task separately authorizes a source documentation update. Prepare the
   article in a clean, current, isolated task branch or worktree of the
   canonical blog repository.
5. Run the blog's article validator, Hugo build, generated-site audit, and
   content checks. Perform desktop/mobile browser verification when the article
   adds media, complex tables, diagrams, embeds, or layout-sensitive content.
   Automated redaction checks are guardrails, not proof of privacy; the agent
   and human approver still inspect the final public diff for context-specific
   sensitive information.
6. Deliver through one focused blog pull request and required deterministic CI.
   AI review remains advisory and must not be triggered merely because an
   article was generated.
7. Merge through the hosting service, then deploy only from the clean canonical
   blog `main` checkout through the canonical deployment command. Root is used
   only for the deployment boundary. Never rsync or write the production tree
   directly from an agent worktree.
8. Verify the public URL, metadata, assets, and production health. Report one
   of `draft_ready`, `pr_open`, `merged_waiting_deploy`, `live`, or `blocked`;
   never describe a merged-but-not-deployed article as live.

If the canonical blog checkout contains unrelated work, sudo is unavailable,
or production gates are not satisfied, stop at `merged_waiting_deploy` or
`blocked`. Do not stash, commit, rebase, discard, or otherwise move another
task's work merely to publish an article without explicit authorization.

Publication does not mutate or approve the source evidence. A live article is
a curated public projection, while project documentation and formal
TEAM-MEMORY remain the internal sources of truth.

## Services And Docker

- Persistent development applications run as enabled `claude` user units in
  `/home/claude/.config/systemd/user`, managed with `systemctl --user`. Do not
  use root `tmux`, `nohup`, or a login shell as a service supervisor.
- Temporary host services should request an automatically assigned port when
  the runtime supports it. A service that needs a stable host endpoint must
  receive an allocation from `DEVELOPMENT-PORT-REGISTRY.md` before startup;
  framework defaults such as `3000`, `5000`, `8000`, and `8080` are not a
  server-wide allocation mechanism.
- Development listeners bind to `127.0.0.1` or `::1` by default. Binding to a
  non-loopback address, publishing a container port on all interfaces, opening
  a firewall path, or adding a public proxy requires an explicit exposure and
  security decision independent of the port number.
- Containers and infrastructure services retain their standard internal ports.
  Prefer service-name networking without host publication; when host access is
  required, map the internal port to a loopback-bound dynamically assigned or
  registered host port. Do not modify an upstream image or protocol merely to
  satisfy the host allocation convention.
- Fixed development host ports must avoid the kernel ephemeral range, IANA
  conflicts, existing listeners, and prior registry allocations. The registry
  is the source of truth for the local static pool and ownership; port numbers
  outside it are exceptions, not precedent.
- System daemons remain root-managed. Do not alter `/etc`, SSH, Nginx, Docker
  daemon configuration, accounts, groups, or system services without explicit
  authorization for that host change.
- Project-scoped Compose work may run as `claude`; Docker daemon administration
  remains a root responsibility. Do not use `/root` paths or perform broad
  image, container, or volume cleanup without explicit approval.

## Emergency Changes

Urgent production work still uses `hotfix/* -> PR -> deterministic CI ->
merge`. Urgency shortens scope and response time; it does not remove review.

Only a real incident in which GitHub or the required review service is
unavailable and waiting would materially worsen impact may use a break-glass
path. It requires explicit human approval in the current task, a recorded
incident reason, the smallest possible change, relevant verification, and
immediate restoration of every disabled guard. A retrospective PR and review
must follow. Agents cannot self-authorize break-glass actions.
