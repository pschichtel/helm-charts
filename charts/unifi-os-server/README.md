# UniFi OS Server 5.1.42 — Docker Compose (no systemd)

Runs the UniFi OS Server components from the official
`ghcr.io/unihosted/unifi-os-server-docker:5.1.42` image as separate foreground
compose services. No systemd anywhere; data tier is all-official images.

## Services

| Service | Role |
|---|---|
| `unifi-core` | OS core (nginx, D-Bus, ucore API). Publishes all ports: 80, 443, 8443, 11051, 11081, 11084. |
| `unifi` | UniFi Network Application (java). 8080/8081 internally. |
| `ulp-go` | ULP app framework (Go). 9080/9443 internally. |
| `unifi-directory` | Directory (Go). 13080 internally. |
| `ucs-agent`, `unifi-identity-update`, `uid-agent` | Identity/UCS agents (Go). |
| `postgres` | Official `postgres:14` (see below). Shared by all Go services. |
| `unifi-os-server-mongodb` | Official `mongo:latest` (for the java app). |
| `rabbitmq` | Official `rabbitmq:latest` (4.x, TLS 5671, user `ui`). |

All app-tier services share the `unifi-core` container network
(`network_mode: service:unifi-core`) and communicate over localhost; only
`unifi-core` publishes ports to the host.

Console: `https://<host>:8443` — first boot is in factory state, complete the
setup wizard.

## Layout

- `docker-compose.yml` — the stack.
- `.env` — `UOS_IMAGE`, `UOS_UUID`.
- `scripts/` — per-service entrypoints (`run-*.sh`), mounted read-only at
  `/scripts` in each container:
  - `run-unifi-core.sh` — applies image patches, runs fake D-Bus
    (`fake-sd1.js`), starts nginx.
  - `run-ulp-go.sh` — waits for postgres, points the app at the shared
    `postgres` service, runs `pre-start.sh` (first-boot `ulp init`), then
    starts the app **as the `ulp-go` user via `runuser`** (root only for the
    bootstrap steps; `runuser` propagates the child's exit code).
  - `run-rabbitmq.sh`, `run-unifi.sh` — official RMQ setup (TLS 5671, `ui`
    user/cert) and java RMQ TLS flags.
- `meta/` — console identity files (`platform`, `product_name`, `app_model`,
  `version`), bind-mounted read-only into all Go services. The image does not
  ship these files; they are the only source of console identity
  (`UOSSERVER.0000000.5.1.42.000000.000000.0000.0000`).
- `postgres/initdb.d/` — runs only on a fresh volume: trust auth, app roles
  and databases (`ulp-go`, `ulp-go-syslog`, ...).

## Postgres must be version 14

`ulp-go` (xorm fork) always emits `... c.relname = $1AND s.table_schema = $2 ...`
(no space after `$1`). Postgres <= 14 accepts that; 15+ rejects it with
`trailing junk after parameter`, which panics `ulp-go` on any boot where tables
already exist. The upstream image bundles PG 14 (and 16), so the compose file
pins `postgres:14` instead of patching the binary. Do not bump it. Changing the
major version requires recreating the `postgres-data` volume.

The volume mount point is tied to the image major version: `postgres:<=17`
declares `VOLUME /var/lib/postgresql/data` (mount there; mounting the parent
would leave the data in an anonymous volume), while `postgres:18+` uses
`/var/lib/postgresql/<major>/docker` and expects the mount at
`/var/lib/postgresql`. Adjust the mount when changing the major version.

## Operations notes

- The data tier is disposable per the requirements: recreating the
  `postgres`/`mongodb`/`rabbitmq` volumes loses state by design.
- If `unifi-core` is ever removed/recreated, force-recreate **all** app-tier
  services (they join its netns): `docker compose up -d --force-recreate`.
- Entry scripts are bind-mounted: after changing `scripts/` or
  `docker-compose.yml`, use `docker compose up -d --force-recreate <svc>`.
- App logs: `/data/<app>/log/` in each Go service (volumes `*-data`);
  panics land in `std.err.log`; the java app logs to
  `/var/lib/unifi/logs/` (volume `unifi-data`).
- RabbitMQ TLS check:
  `docker exec unifi-os-rabbitmq runuser -u rabbitmq -- env HOME=/var/lib/rabbitmq RABBITMQ_NODENAME=rabbit@localhost rabbitmqctl list_connections`
  (expect the `ui` connection on 5671).
