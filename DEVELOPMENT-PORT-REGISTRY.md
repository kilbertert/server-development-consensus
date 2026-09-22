# Development Port Registry

This is the canonical registry for fixed host ports used by development
services on this server. It does not assign container-internal or standard
infrastructure ports.

## Static Pool

- New fixed development host ports use `11000-14999`.
- The pool is a local convention, not an IANA reservation. Before allocation,
  check the IANA registry, this file, and current TCP and UDP listeners.
- Do not allocate from the host ephemeral range. At adoption, Linux uses
  `32768-60999`; recheck `/proc/sys/net/ipv4/ip_local_port_range` before changing
  the pool or host network configuration.
- Allocate one port only when a stable host endpoint is required. Temporary
  services should use automatic allocation.
- Bind to loopback unless external access is explicitly authorized.
- Remove an allocation when its service is retired. Historical changes remain
  available in Git.

## Allocations

Add one row in ascending port order before starting a new fixed service.

| Port | Protocol | Bind address | Project/service | Owner | Purpose | Lifecycle |
| ---: | --- | --- | --- | --- | --- | --- |
| 12101 | TCP | 127.0.0.1 | healthcare verification instance / application | claude | Baseline verification instance for the healthcare project (HTTP) | active |
| 12106 | TCP | 127.0.0.1 | healthcare verification instance / relational database | claude | Desensitized copy of the production health database | active |
| 12107 | TCP | 127.0.0.1 | healthcare verification instance / cache | claude | Cache for the healthcare verification instance | active |
| 12108 | TCP | 127.0.0.1 | healthcare verification instance / configuration service | claude | Configuration service for the healthcare verification instance | active |

## Existing Exceptions

Services established before this policy may retain documented host ports
outside the pool. New services must not copy those exceptions, and existing
services should be migrated only through a separately verified change.

Add one row in ascending port order when a pre-policy service is first recorded
or reconciled. These are recorded as they run, never renumbered: the registry
exists to state the real value an auditor can confirm, and inventing a pool-shaped
number for a live listener would make it wrong.

| Port | Protocol | Bind address | Project/service | Owner | Purpose | Lifecycle |
| ---: | --- | --- | --- | --- | --- | --- |
| 8100 | TCP | 0.0.0.0 | linkedin-lead-gen / API | claude | Lead generation API (basic auth at the application) | active |
| 8125 | TCP | 127.0.0.1 | genesis-evidence / evidence API | claude | Read-only published-evidence API; deliberate internal edge for Health-Flow, never a user domain | active |
| 8126 | TCP | 127.0.0.1 | genesis-evidence / review workbench | claude | Paper acquisition, extraction and review workbench (Bearer-gated) | active |
| 8127 | TCP | 127.0.0.1 | health-flow / user application | claude | Patient report portal and report API; public entry is `genesis-evidence.ranlei.work` | active |

Exposure is not implied by a row. `8100` binds a non-loopback address and is
recorded debt (see `fleet-ops/FLEET.md` §3.2). The three loopback rows pair with
`fleet-ops/FLEET.md` §3.2 A, `docs/deployment.md` and `health-flow/ops/README.md`
for the entry chain and its security decision.
