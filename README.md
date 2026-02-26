# ZiggySpiderNode

Standalone node runtime binaries for the Acheron/Spiderweb ecosystem.

This repo exists so node operators (Windows/Linux/macOS) can build and run
node daemons without cloning the full `ZiggySpiderweb` server repository.

## Build

```bash
zig build -Doptimize=ReleaseSafe
```

Binary output:

- `zig-out/bin/spiderweb-fs-node`

## Run (invite pairing)

```bash
./zig-out/bin/spiderweb-fs-node \
  --export "work=.:rw" \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --pair-mode invite \
  --invite-token "inv-..." \
  --node-name "edge-node"
```

## Pairing State and Recovery

- Pairing credentials are persisted in the node state file (`--state-file`, defaults to `./spiderweb-fs-node-state.json`).
- If the control server rejects saved credentials (`node_not_found` / `NodeNotFound`), the node now clears stale local state and automatically re-enters pairing mode.
- For invite mode, keep a valid invite token available so unattended re-pair can succeed after server resets.

## Dependencies

- `ziggy_spider_protocol` (local path dependency in `build.zig.zon`)
  - provides `spiderweb_fs` and `spiderweb_node` shared modules.
