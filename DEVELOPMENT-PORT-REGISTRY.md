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
| 11422 | TCP | 0.0.0.0 | paper-hub.service | claude | paper-hub development HTTP endpoint via FRP | active |
| 11880 | TCP | 127.0.0.1 | auto-test observation dashboard (easy dashboard --port) | claude | Auto-Test read-only observation plane; FRP-tunneled to auto-test.ranlei.work | active |

## Existing Exceptions

Services established before this policy may retain documented host ports
outside the pool. New services must not copy those exceptions, and existing
services should be migrated only through a separately verified change.
