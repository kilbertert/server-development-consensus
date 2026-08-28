# Server Governance Context

This context defines the shared language for server-wide development governance and project-level AFK automation. It describes ownership and boundaries, not implementation details.

## Governance

**Governance invariant**:
A condition that must hold across every execution plane, such as account boundaries, protected-branch delivery, or secret isolation.
_Avoid_: best practice, suggestion

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
