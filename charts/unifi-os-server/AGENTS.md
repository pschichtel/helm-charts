# Agent notes

This directory is a Helm chart (`charts/unifi-os-server`) that runs the services of
the UniFi OS Server image (`ghcr.io/unihosted/unifi-os-server-docker`) as one
pod with one container per former systemd unit. PostgreSQL, MongoDB and
RabbitMQ are external. It also holds the chart's development material
(`test/`, `examples/`, `docs/`, `ct.yaml`), excluded from the package via
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
- User-facing chart docs live in `README.md.gotmpl` and
  the `# --` comments in `values.yaml`; regenerate the chart README with
  `helm-docs` after changing either.

## No custom images

- Do not build or introduce custom container images (no `Dockerfile`, no
  locally built or tagged images). Every container must use a stock image
  (the UniFi OS Server image, or official upstream images for anything else).
- Needed changes belong in the chart: entrypoint scripts and config shipped as
  ConfigMaps (`files/`), volumes and pod settings.
  Running an entrypoint as root to prepare the container is acceptable; see
  `files/scripts/as-user.sh`.

## Chart conventions

- Bump `version` in `Chart.yaml` for every chart change; `appVersion` follows
  the default image tag.
- New values need a `# --` comment and an entry in `values.schema.json`.
- Credentials only ever come from existing Secrets; never render secrets
  from values.

## Testing

- Static: `ct lint --config charts/unifi-os-server/ct.yaml`, and
  `helm template t charts/unifi-os-server -f charts/unifi-os-server/test/e2e/values.yaml | kubeconform -strict -kubernetes-version 1.26.0 -`.
- End to end: `charts/unifi-os-server/test/e2e/setup.sh` then `charts/unifi-os-server/test/e2e/run.sh` (kind, the three
  operators; see `test/e2e/README.md`). Run it for changes to entrypoints or
  the deployment; it checks readiness, zero restarts, `helm test` and the
  setup wizard. For changes to the PostgreSQL settings, also run it with
  `POSTGRES_PROVISIONER=db-operator`.
