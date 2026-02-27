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
- `zig-out/bin/spiderweb-echo-driver` (reference `native_proc` namespace driver)
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
  "help_md": "Camera namespace driver"
}
```

Notes:

- `{node_id}` is expanded at runtime after pairing resolves the real node ID.
- `enabled: false` can be used to keep a manifest file present but inactive.
- Built-in FS/terminal providers and manifest services share one catalog namespace; duplicate service IDs are rejected.

### Reference Driver Invoke Flow

The included `spiderweb-echo-driver` consumes JSON from stdin and returns JSON
on stdout. With `echo.json` loaded, the service is projected as a namespace
mount (`/nodes/<node_id>/echo`) with:

- `control/invoke.json` (write JSON payload)
- `control/reset` (write any payload to reset state files)
- `result.json` (driver stdout)
- `status.json`
- `metrics.json`
- `last_error.txt`

Additional runtime examples:

- `examples/services.d/echo-inproc.json`: in-process dynamic library driver
  (`runtime.type = native_inproc`)
- `examples/services.d/echo-wasm.json`: WASI module driver via runner
  (`runtime.type = wasm`, `runner_path = wasmtime`)

## Pairing State and Recovery

- Pairing credentials are persisted in the node state file (`--state-file`, defaults to `./spiderweb-fs-node-state.json`).
- If the control server rejects saved credentials (`node_not_found` / `NodeNotFound`), the node now clears stale local state and automatically re-enters pairing mode.
- For invite mode, keep a valid invite token available so unattended re-pair can succeed after server resets.

## Dependencies

- `ziggy_spider_protocol` (local path dependency in `build.zig.zon`)
  - provides `spiderweb_fs` and `spiderweb_node` shared modules, including
    service manifests, namespace-driver runtime descriptors, and plugin loader scaffolding.
