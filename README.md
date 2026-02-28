# ZiggySpiderNode

Standalone node runtime binaries for the Acheron/Spiderweb ecosystem.

This repo exists so node operators (Windows/Linux/macOS) can build and run
node daemons without cloning the full `ZiggySpiderweb` server repository.

## Build

```bash
zig build -Doptimize=ReleaseSafe
```

## Linux-Side Windows Build Verification

You can validate Windows outputs from Linux using cross-compilation:

```bash
TARGET=x86_64-windows-gnu OPTIMIZE=ReleaseSafe RUN_WINE_SMOKE=0 ./scripts/check-windows-build.sh
```

Optional execution smoke test (if `wine`/`wine64` is installed):

```bash
TARGET=x86_64-windows-gnu RUN_WINE_SMOKE=1 ./scripts/check-windows-build.sh
```

What it verifies:

- `spiderweb-fs-node.exe` builds
- reference driver artifacts build (`.exe`, `.dll`, `.wasm`)
- optional `--help` run of `spiderweb-fs-node.exe` through Wine

Binary output:

- `zig-out/bin/spiderweb-fs-node`
- `zig-out/bin/spiderweb-echo-driver` (reference `native_proc` namespace driver)
- `zig-out/bin/spiderweb-web-search-driver` (reference `native_proc` web search driver)
- `zig-out/lib/libspiderweb-echo-driver-inproc.so` (reference `native_inproc` driver on Linux; platform-specific filename)
- `zig-out/bin/spiderweb-echo-driver-wasm.wasm` (reference WASI driver module)

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

## Built-in Terminal Service

Use `--terminal-id <id>` (repeatable) to publish executable terminal namespace
services alongside FS:

```bash
./zig-out/bin/spiderweb-fs-node \
  --export "work=.:rw" \
  --terminal-id "1" \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --pair-mode invite \
  --invite-token "inv-..." \
  --node-name "edge-node"
```

Each terminal service is exposed as:

- service id: `terminal-<id>`
- mount: `/nodes/<node_id>/terminal/<id>`
- invoke path: `control/invoke.json`

Invoke payload examples:

```json
{"command":"echo hello from terminal"}
```

```json
{"argv":["/bin/sh","-lc","echo hello"],"cwd":".","max_output_bytes":65536}
```

## Add Extra Services (Manifest)

`spiderweb-fs-node` can advertise additional namespace services via JSON manifests:

- `--service-manifest <path>` (repeatable)
- `--services-dir <path>` (repeatable, loads `*.json`)

Example:

```bash
./zig-out/bin/spiderweb-fs-node \
  --export "work=.:rw" \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --pair-mode request \
  --manifest-reload-interval-ms 2000 \
  --service-manifest ./examples/services.d/echo.json \
  --services-dir ./services.d
```

Manifest shape (minimum):

```json
{
  "service_id": "camera-main",
  "kind": "camera",
  "state": "online",
  "endpoints": ["/nodes/{node_id}/camera"],
  "capabilities": { "still": true },
  "mounts": [
    {
      "mount_id": "camera-main",
      "mount_path": "/nodes/{node_id}/camera",
      "state": "online"
    }
  ],
  "ops": { "model": "namespace", "style": "plan9" },
  "runtime": {
    "type": "native_proc",
    "abi": "namespace-driver-v1",
    "executable_path": "./zig-out/bin/spiderweb-echo-driver"
  },
  "permissions": { "default": "deny-by-default" },
  "schema": { "model": "namespace-mount" },
  "invoke_template": {},
  "help_md": "Camera namespace driver"
}
```

Notes:

- `{node_id}` is expanded at runtime after pairing resolves the real node ID.
- `enabled: false` can be used to keep a manifest file present but inactive.
- Built-in FS/terminal providers and manifest services share one catalog namespace; duplicate service IDs are rejected.
- `invoke_template` (object, optional) seeds namespace `TEMPLATE.json`/`template.json`.

### Reference Driver Invoke Flow

The included `spiderweb-echo-driver` consumes JSON from stdin and returns JSON
on stdout. With `echo.json` loaded, the service is projected as a namespace
mount (`/nodes/<node_id>/echo`) with:

- `control/invoke.json` (write JSON payload)
- `control/reset` (write any payload to reset state files)
- `SCHEMA.json` / `schema.json`
- `TEMPLATE.json` / `template.json`
- `result.json` (driver stdout)
- `status.json`
- `metrics.json`
- `last_error.txt`
- `config.json` (runtime policy input)
- `health.json` (runtime + supervision state)
- `HOST.json` (runtime host contract metadata)

`config.json` can carry optional supervision policy for executable services:

```json
{
  "supervision": {
    "max_consecutive_failures": 3,
    "max_consecutive_timeouts": 2,
    "cooldown_ms": 5000,
    "auto_disable_on_threshold": true
  }
}
```

Additional runtime examples:

- `examples/services.d/echo-inproc.json`: in-process dynamic library driver
  (`runtime.type = native_inproc`)
- `examples/services.d/echo-wasm.json`: WASI module driver via runner
  (`runtime.type = wasm`, `runner_path = wasmtime`)
- `examples/services.d/web-search.json`: native process web search namespace
  service (`runtime.type = native_proc`)

## Pairing State and Recovery

- Pairing credentials are persisted in the node state file (`--state-file`, defaults to `./spiderweb-fs-node-state.json`).
- Namespace service runtime state is persisted beside it as
  `<state-file>.runtime-services.json` (control ops, supervision config, metrics,
  and surfaced status/error/result files), and restored on next start.
- Manifest files are polled for hot reload in control-tunnel mode (default every
  2000ms, configurable via `--manifest-reload-interval-ms`).
- If the control server rejects saved credentials (`node_not_found` / `NodeNotFound`), the node now clears stale local state and automatically re-enters pairing mode.
- For invite mode, keep a valid invite token available so unattended re-pair can succeed after server resets.

## Dependencies

- `ziggy_spider_protocol` (local path dependency in `build.zig.zon`)
  - provides `spiderweb_fs` and `spiderweb_node` shared modules, including
    service manifests, namespace-driver runtime descriptors, and plugin loader scaffolding.
