---
status: accepted
---

# Multi-Host Development Model

This spec fixed the model that the `Host Fleet And Multi-Host Development`
section only sketched. Those rules are now in the baseline, so this document
is the rationale behind them and the record of what was deliberately left out
rather than a second source of rules. It defines what a service host is, how a
service identity is separated from a development identity, when a service
moves between hosts, what "moved" means, and where these rules are enforced.

The concrete fleet inventory — addresses, access methods, account names, and
where credentials are kept — is internal operating record and stays in the
private operations record. This document states rules and criteria only. A
rule that needs an address to be understood is written wrong.

## Problem Statement

The server was built on the assumption of one machine. Policy, project
source, user services, public entry points, and the development port registry
all live on the same host, under one interactive account. That assumption is
now retired: a second host exists, carries a project's production service,
and more services are expected to follow it.

Five problems follow, none of which the current baseline can express.

**1. The intended end state has no role.** The baseline defines
`project production host` as carrying exactly one project's service. A host
intended to carry *every* project's services is a different thing, and the
baseline also says that a host without a declared role is outside the policy
and forbidden for agent work. The end state the operator wants is therefore
currently inexpressible, and the host already running in that direction is
technically undeclared.

**2. Exposures were never decided, only inherited.** Because one host was
both the development host and the de-facto service host, services on it bind
non-loopback addresses and are reachable from the public internet. Some are
reached through a tunnel; some bind non-loopback with no tunnel at all. The
baseline requires each exposure to be "an explicit security decision
recorded with the host", and for these there is no record and no decision —
the exposure is a side effect of where the service was first started.

**3. There is no migration contract.** Nothing states when a service should
move, what evidence makes a move complete, or how to get back. Every
migration is therefore improvised under time pressure, and the improvisation
is different each time. The one migration performed so far produced a good
procedure; nothing captures it.

**4. Credentials are protected by accident.** Access material lives in
private records as plaintext and in per-project `.env` files whose only
protection is file mode. This works while exactly one identity can read
them, and it is the reason a shared service identity is unsafe: the same
mode that keeps a credential private keeps it private from *everyone else*
only as long as no second project shares the identity.

**5. Drift between merged policy and installed policy is invisible.**
The installed copy can be older than the merged source and no agent notices
— agents read the installed copy. This was observed directly: a baseline
revision defining the host fleet was merged and not installed, so every
agent on the host was still operating under the previous rules.

## Solution

Declare the missing role, state the invariant that separates the two kinds
of host, give every project its own service identity, and make migration a
contract instead of an improvisation. Enforce all of it through the seams
that already exist — the canonical installer and the policy audit — rather
than by adding tooling.

In one sentence: **a development host develops, a service host serves, no
host does both, and the rules that say so are checked by machinery that is
already installed.**

## User Stories

1. As the operator, I want every host I own to have exactly one declared
   role, owner, purpose, and lifecycle, so that I can tell what a machine is
   for without reading its process list.
2. As the operator, I want a role for a host that carries many projects'
   services, so that the end state I am moving toward is a legal state.
3. As the operator, I want the development host to carry no public service,
   so that "this machine is for development" is a fact and not an aspiration.
4. As the operator, I want a second kind of service host that belongs to one
   project alone, so that I can still give an important project its own
   machine without inventing another role later.
5. As the operator, I want each project on a service host to run under its
   own system identity, so that a defect in one project does not become
   access to every other project's data and credentials.
6. As the operator, I want that separation to be the *default* rather than a
   hardening step, so that adding a project does not add a security review.
7. As the operator, I want a service identity that cannot log in and cannot
   escalate, so that a compromise of a service does not yield a shell or
   sudo on the host.
8. As the operator, I want each host to keep its own port allocations from a
   disjoint pool, so that a port number means the same thing on every host
   and two hosts cannot silently collide.
9. As the operator, I want the port registry to remain a single reviewed
   file rather than per-host prose, so that an allocation has one history.
10. As the operator, I want a host's internal service ports to bind loopback
    by default, so that exposing a port is always a decision I made.
11. As the operator, I want every non-loopback exposure recorded with the
    host that owns it, so that I can answer "what is reachable from the
    internet" without scanning.
12. As the operator, I want a service to move to a service host when it is
    next touched, so that migration is paid for out of work I am already
    doing instead of as a project of its own.
13. As the operator, I want a criterion — not a schedule — for the first
    batch of moves, so that the list cannot go stale.
14. As the operator, I want a service's deployment assets versioned in the
    project repository, so that "how this is deployed" is reviewable and
    reproducible rather than remembered.
15. As the operator, I want a moved service to have an executable acceptance
    check whose result is recorded, so that "it works" is evidence and not
    an impression.
16. As the operator, I want the old and new deployment to run in parallel
    until acceptance passes, so that rolling back is a routing change and
    not a rebuild.
17. As the operator, I want switching traffic and retiring the old instance
    to be two separate steps, so that I never lose the rollback path in the
    same action that proves the new path.
18. As the operator, I want the public entry point itself to move as one
    deliberate, canaried change, so that moving it cannot strand services
    whose configuration is split across two hosts.
19. As the operator, I want credentials to live in one encrypted inventory
    with the decryption key held only by me, so that a leaked private
    directory is not a leaked fleet.
20. As the operator, I want that inventory to record *where* a secret is
    kept rather than the secret itself wherever possible, so that the
    inventory does not become the single thing worth stealing.
21. As the operator, I want the inventory outside version control, so that
    the map of the fleet is not published alongside the rules for it.
22. As an agent, I want the installed policy to be provably current, so that
    I am not enforcing rules that were replaced.
23. As an agent, I want a machine-readable statement of which host I am on
    and what that host is allowed to do, so that I can refuse work that
    belongs on a different host instead of guessing.
24. As an agent, I want service hosts to be declared off-limits for
    development, so that I do not edit running code because it was the
    convenient place to fix it.
25. As a project maintainer, I want a documented migration procedure I can
    follow without asking, so that moving a project is routine.
26. As the operator, I want the CI runner fleet to stay on the development
    host, so that a machine built for serving users is not also running
    arbitrary branches.
27. As the operator, I want to know which deliberate simplifications are
    carrying risk, so that I can revisit them when the fleet grows rather
    than rediscovering them.

## Implementation Decisions

### Roles

The baseline's role list gains one entry and keeps its existing entries.

- **`service host`** — carries the deployable services of *more than one*
  project for real users. It is deployed to, never developed on. Each
  project on it gets its own service identity, its own service layout under
  a project-scoped root, and its own ports.
- **`project production host`** — unchanged, and still the right role when a
  project is important enough to warrant a machine that carries nothing
  else. A host that later gains a second project stops being this and
  becomes a `service host`; that transition is a recorded role change, not
  a drift.

A host may hold exactly one role. Role changes, public entry-point moves,
and host retirement are deliberate changes with the same evidence and review
requirements as a code change.

### Development host invariant

The development host carries no service reachable from outside the
development plane. Concretely: no process on it binds a non-loopback address
for the purpose of serving a real user, and no public entry point is
terminated on it.

This invariant is what makes the two roles mutually exclusive rather than
merely different in emphasis. Services currently violating it are debt, not
exceptions, and the batch criterion below is how the debt is worked off.

### Service identity

Scope of a service identity is **one project**, not one process. A project's
backend, worker, and any future process run as the same identity, which
keeps the number of identities proportional to the number of projects rather
than the number of processes.

Each service identity is a system account: no login shell, no password, no
sudo, no membership in a shared group, home under the project's service
root. Services run under the host's system service manager as that identity,
never as `root`, never as an interactive account, and never as an unmanaged
foreground process.

**Rejected alternative — a shared service identity for all projects.** It
was considered for simplicity and rejected. The reasoning is recorded
because the trade-off is real and will be proposed again:

- The saving is a small number of account-creation lines.
- The cost is that credential files protected by ownership and mode become
  readable by every service on the host, so a single defect in any one
  project yields every other project's production credentials — with no
  privilege escalation and no lateral movement required.
- The compensating control that would restore the boundary (injecting
  secrets via the service manager's credential mechanism, so no service
  identity can read a credential file) is more machinery than the
  per-project account it replaces.

There is also a consistency argument: the existing pilot service host
already runs its project under a project-scoped system identity. Adopting a
shared identity would be a change *away* from the current state, with a
production restart and a recursive ownership change, in exchange for
security debt.

### Ports

Each host owns a registry of the fixed ports it allocates. Pool ranges are
disjoint across hosts, and the development port registry keeps claiming only
its own range.

- The development pool stays as it is today.
- Service hosts draw from a separate, higher pool reserved for them.
- A service host's internal service ports bind loopback and are declared
  with that host, not with the development registry.
- A port inherited from a host being migrated away from may be retained as a
  recorded exception when changing it would require touching the
  application. New services do not copy such exceptions.

### Connectivity and trust planes

The fleet has two planes and they are deliberately not the same.

- **Development plane.** A private overlay network carries machine-to-machine
  access between the development host and hosts that run agent or CI work.
  Membership of this plane is not the same as membership of the fleet, and
  joining it is a recorded decision.
- **Service plane.** Service hosts are reached over public SSH with public
  key authentication only, with the cloud firewall restricted to known
  sources. A service host does not join the development overlay, because
  that would make its reachability depend on a third-party control plane and
  a personal account.

Password authentication is disabled on every host. A host's management
interfaces bind loopback or the private plane; the only services binding a
non-loopback address are the intended public entry points.

### Policy distribution

The governance release unit is installed on hosts that run agents or
adjudicate review. A service host receives only its projects' deployment
artifacts. This follows from the roles: if no agent session runs on a
service host, installing rules that constrain agent sessions there adds
surface without adding control.

### Migration contract

When a service moves to a service host:

1. Its deployment assets are versioned in the project repository.
2. It has an executable acceptance check, and the result is recorded with
   the build identity, environment, and timestamp.
3. The old and new deployments run in parallel until acceptance passes.
4. Traffic switch and old-instance retirement are separate steps; the
   previous deployment stays recoverable until the switch is verified.
5. The public entry point, if it must move, moves once, deliberately, behind
   a canary on a new name before any production name is repointed.

**Batch criterion.** Migration is triggered by work, not by a schedule: a
new service is deployed to a service host directly, and an existing service
moves when it is next changed. The first batch is the set of services that
bind a non-loopback address with no tunnel in front of them — they are the
ones with neither a reason to be on the development host nor a recorded
exposure decision. After that batch, no batch table is maintained, because a
list that is not derived from a criterion goes stale.

### Credentials

Access material moves into one encrypted inventory, stored outside version
control in the private operations directory, encrypted to a key held by the
operator alone.

The inventory holds host entries (role, owner, access path), data-source
pointers, entry-point secrets, and, for each project, *where* its environment
file lives. It holds secrets themselves only where no indirection is
possible.

Existing plaintext credentials are migrated entry by entry as the service
they belong to is touched, and removed from the plaintext record once
migrated — not in one sweep, which would break every dependent at once.

### Runner placement

The self-hosted CI runner fleet stays on the development host and is part of
that role. Runners are consumers of the development flow, not user-facing
services, and a service host's restricted egress makes it a poor runner
host anyway. Converting the runners to one-job-per-runner instances is a
known improvement and is deliberately deferred.

## Testing Decisions

Governance changes are verified by enforcement, not by unit tests. The
question a check must answer is: *can this rule be violated without anyone
noticing?*

**One seam.** All new checks attach to the policy audit that already runs on
a timer and already implements the existing invariants. No new tool, no new
unit, no second place where "the rules" are inspected. When a rule in this
spec is not checked there, it is a convention, and the spec should say so
rather than imply enforcement.

Candidate checks, in the vocabulary the audit already uses:

- Installed policy content matches merged source, so drift is a failure
  rather than a discovery.
- The port registry is present, well-formed, and not drifted.
- Worktree lifecycle findings are reported without failing a first-time
  migration window.

**What makes a good check here.** It observes external state (a file's
content, a listening socket, a process's identity) rather than internal
wiring; it fails closed; it stays silent when correct; and it can run
without network access or agent participation.

A check that requires an agent to report on itself is not a check.

**Which hosts are checked.** Only hosts carrying the governance release unit
are audited by it. A service host is verified by its project's acceptance
script, not by the policy audit, and that distinction is intentional.

**Acceptance scripts as the service-host seam.** Per-project acceptance
checks are the highest available seam for "is this service actually
working", and they exist already in the pilot project. This spec makes them
a requirement of moving a service rather than a per-project nicety.

## Out of Scope

- Configuration-management or provisioning frameworks (agentless or
  otherwise), and declarative image-based hosts. Below a handful of hosts
  these cost more than they return; the threshold to revisit is a fleet size
  that makes hand-applied rules unreliable.
- Self-hosted overlay control planes, SSH certificate authorities, and
  external secret managers. Each needs a scale of collaborators or hosts
  this fleet does not have.
- A second development host. The baseline allows it as a deliberate split;
  this spec does not create the split, and the invariant above would need
  restating if it happened.
- Container image distribution to service hosts, including whether services
  should be containerised there at all.
- TLS termination, certificate issuance, and DNS for any service host.
- Converting CI runners to ephemeral instances.
- Repository-level delivery differences; those are governed elsewhere.

## Further Notes

**Accepted risks, recorded so they can be revisited.**

- The development plane runs on a personal account of a third-party overlay
  service, so availability and access policy for that plane depend on that
  account. Accepted because the alternative is operating a control plane.
- The runner fleet remains persistent rather than ephemeral. Accepted while
  runner-backed repositories accept no untrusted pull-request code.
- Service hosts remain reachable over public SSH rather than moving to
  private-plane-only access. Accepted because it keeps production
  reachability independent of the overlay provider; the control is key-only
  authentication plus a firewall restricted to known sources.

**Deliberately not built.** The operator's stated direction is covered by
the roles, the invariant, and the migration contract. Everything else that
was considered (see Out of Scope) is downstream of a scale this fleet has
not reached, and each item names its own trigger.

**Where the concrete plan lives.** The inventory, the per-service migration
checklist, the credential relocation order, and the addresses are written in
the private operations record, not here. If this spec and the baseline
disagree about a *rule*, the baseline wins; this document carries no rule of
its own. If the spec and the record disagree about an *inventory fact*, the
record wins.
