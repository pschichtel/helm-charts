# Agent notes

This directory is a Helm chart (`charts/unifi-os-server`) that runs the UniFi OS
Server image (`ghcr.io/unihosted/unifi-os-server-docker`) as one container
with the image's own systemd, like the upstream compose file. PostgreSQL,
MongoDB and RabbitMQ are external. It also holds the chart's development material
(`test/`, `docs/` including `docs/examples/`, `ct.yaml`), excluded from the package via
`.helmignore`. Paths are relative to this directory; run commands from the
repository root. See `README.md` for layout and findings. The chart is
meant to be published, so treat values, docs and defaults as public API.

## Documentation policy

- Record every non-obvious finding in `README.md`: root causes of bugs,
  workarounds, version pins (and why), differences from the stock image, and
  anything that surprised you. These notes are what we rely on when upgrading
  the image to newer versions, so include the *why* and how to verify whether
  it still applies.
- Prefer fixing the environment (e.g. pinning a compatible upstream version)
  over patching binaries or image contents. If a patch is unavoidable, document
  it in the README with the root cause.
- When a workaround is removed, update the README in the same change.
- Keep the architecture diagrams in the README in sync when adding/removing
  services or changing ports.
- Keep comments in `values.yaml` to the bare minimum (style of the other
  charts in the repository): only what the key name and default do not make
  obvious, e.g. template-side defaults. Explanations belong in `README.md`.

## No custom images

- Do not build or introduce custom container images (no `Dockerfile`, no
  locally built or tagged images). Every container must use a stock image
  (the UniFi OS Server image, or official upstream images for anything else).
- Needed changes belong in the chart: `files/boot.sh` (shipped as a
  ConfigMap), volumes and pod settings.
- Change the image's behaviour only with systemd means written by
  `files/boot.sh` (masks, new units, drop-ins under `/etc/systemd/system`);
  never edit the image's unit files or app configs. Leave everything else to
  the image, so that image and app updates need no chart changes.

## Chart conventions

- Bump `version` in `Chart.yaml` for every chart change; `appVersion` follows
  the default image tag.
- Credentials only ever come from existing Secrets; never render secrets
  from values.

## Testing

- Static: `ct lint --config charts/unifi-os-server/ct.yaml`, and
  `helm template t charts/unifi-os-server -f charts/unifi-os-server/test/e2e/values.yaml | kubeconform -strict -kubernetes-version 1.26.0 -`.
- End to end: `charts/unifi-os-server/test/e2e/setup.sh` then `charts/unifi-os-server/test/e2e/run.sh` (kind, the three
  operators; see `test/e2e/README.md`). Run it for changes to `boot.sh` or
  the deployment; it checks readiness, zero restarts, `helm test` and the
  setup wizard. For changes that touch apps, settings or persistence, also do
  the manual checks in `test/e2e/README.md`.
