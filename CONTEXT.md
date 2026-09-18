# Server Governance Context

This context defines the shared language for server-wide development governance and project-level AFK automation. It describes ownership and boundaries, not implementation details.

## Governance

## Host Fleet

**Host fleet**:
The set of hosts with a declared role, owner, and access path that this policy governs. It starts with the interactive development host and grows only through recorded decisions.
_Avoid_: server list, infrastructure inventory

**Development host**:
The interactive host where project source, the `claude` account, user services, and the port registry live. It is the only host where agents develop.
_Avoid_: dev box, workspace server

**Project production host**:
A host that runs exactly one project's deployable service for real users and is deployed to rather than developed on.
_Avoid_: prod server, live machine

**Shared service host**:
A host that backs one or more projects with a database, queue, proxy, or comparable dependency rather than an application of its own.
_Avoid_: database box, infra host

**Governance invariant**:
A condition that must hold across every execution plane, such as account boundaries, protected-branch delivery, or secret isolation.
_Avoid_: best practice, suggestion

**Repository class**:
The declared owner of a repository's delivery process: `server-managed` when this host's workspace owns the task branch, pull request, and merge flow, or `externally governed` when another organization does. It decides which parts of the policy apply and never waives the account boundary or secret isolation.
_Avoid_: repo type, trust level

**Server-managed repository**:
A repository in the workspace whose delivery process this host owns, so the full consensus policy applies. This is the default class.
_Avoid_: our repository, internal project

**Externally governed repository**:
A repository whose review, merge, and release process belongs to another organization. It keeps its own commit convention, hooks, and delivery workflow; this host still enforces the account boundary, secret isolation, worktree location, ports, and host rules.
_Avoid_: third-party repository, vendor project

**Server governance baseline**:
The authoritative, non-decreasing policy published by `server-development-consensus` for all projects, sessions, runners, and tools.
_Avoid_: global defaults, shared guidelines

**Execution adapter**:
A project-level workflow that maps the server governance baseline to a repository's language checks, issue lifecycle, runner, container, and pull-request operations.
_Avoid_: second policy, AFK governance

**Execution plane**:
One of the places where work runs: an interactive session, a host runner, a Docker agent, or GitHub's CI/Ruleset service.
_Avoid_: environment, agent

**Delivery boundary**:
The host-and-GitHub boundary at which a task branch is pushed, a pull request is opened, deterministic checks run, and the protected default branch may be merged.
_Avoid_: deployment boundary, merge script

## Contracts

**Portable policy check**:
A small, fail-closed check that can run inside an AFK container without installing the server account's global configuration. It covers only observable container-safe invariants and does not replace host or GitHub enforcement.
_Avoid_: copied global hooks, full installer

**Compatibility window**:
A SemVer range declaring which `server-development-consensus` releases an AFK template can safely adapt to. An out-of-range or missing declaration blocks delivery.
_Avoid_: template age, advisory version

**Structured exception**:
A machine-readable, owner-approved record for a bounded implementation difference. It includes the invariant, reason, scope, compensating control, approval, and expiry; it cannot relax security or protected-branch invariants.
_Avoid_: workflow comment, informal override

**Task identity**:
The durable GitHub issue and pull-request chain that links confirmed requirements, AFK execution, review, QA, and merge. A chat session may inform the chain but is not its source of truth.
_Avoid_: chat thread, agent run

**Delegated developer**:
An AFK agent running with task-scoped permissions and the same governance invariants as an interactive developer, while lacking host-maintenance and default-branch authority.
_Avoid_: untrusted worker, autonomous maintainer
