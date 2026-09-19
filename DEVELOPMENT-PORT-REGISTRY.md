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
