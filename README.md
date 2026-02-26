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

## Dependencies

- `ziggy_spider_protocol` (local path dependency in `build.zig.zon`)
  - provides `spiderweb_fs` and `spiderweb_node` shared modules.
