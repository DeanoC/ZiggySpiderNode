# ZiggySpiderNode

Standalone node runtime binaries for the Acheron/Spiderweb ecosystem.

ZiggySpiderNode exists so operators can run node daemons on Linux/macOS/Windows without cloning the full server repo. It exports filesystem roots and services that Spiderweb projects into WorldFS.

Learn more:
- `docs/overview.md`
- `docs/README.md`

## Quick Build

```bash
zig build -Doptimize=ReleaseSafe
```

## Quick Run (Invite Pairing)

```bash
./zig-out/bin/spiderweb-fs-node \
  --export "work=.:rw" \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --pair-mode invite \
  --invite-token "inv-..." \
  --node-name "edge-node"
```
