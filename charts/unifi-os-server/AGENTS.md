# Agent notes

This repo splits the UniFi OS Server image (`ghcr.io/unihosted/unifi-os-server-docker`)
into one docker compose service per systemd unit. See `README.md` for layout.

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
