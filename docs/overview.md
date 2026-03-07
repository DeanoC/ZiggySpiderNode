# SpiderNode Overview

SpiderNode provides the standalone node runtime binaries for the Acheron/Spiderweb ecosystem. It lets operators run node daemons on Linux, macOS, or Windows without cloning the full server repo.

## Role in the Stack

- Node runtimes export filesystem roots and services over Acheron.
- Spiderweb’s control plane pairs nodes, manages leases, and projects node services into the unified namespace.
- Agents interact with node resources through the `/nodes/<node_id>/...` namespace.

## What You Can Do

- Export local folders as filesystem mounts.
- Publish terminal namespaces and other services.
- Advertise custom services via JSON manifests.
- Run pairing flows (invite or manual approval) against Spiderweb.

## Key Binaries

- `spiderweb-fs-node` - node daemon that exports filesystem + services
- Reference drivers:
  - `spiderweb-echo-driver`
  - `spiderweb-web-search-driver`

## Next Steps

- `operations/fs-node.md` for pairing and service examples.
- `../deps/spider-protocol/docs/protocols/namespace-driver-abi-v1.md` for driver ABI details.
