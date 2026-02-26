# Service Manifest Examples

- `camera.json`: enabled example native process camera namespace
- `gdrive.json`: disabled example cloud-drive namespace

Run with:

```bash
./zig-out/bin/spiderweb-fs-node \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --service-manifest ./examples/services.d/camera.json
```

Or load all JSON manifests in the directory:

```bash
./zig-out/bin/spiderweb-fs-node \
  --control-url "ws://<server>:18790/" \
  --control-auth-token "<admin-token>" \
  --services-dir ./examples/services.d
```
