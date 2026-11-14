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
| `postgres` | Official `postgres:18`. Shared by all Go services. |
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
  - `patch-ulp-go-app.sh` — see "Known upstream bug" below.
  - `run-rabbitmq.sh`, `run-unifi.sh` — official RMQ setup (TLS 5671, `ui`
    user/cert) and java RMQ TLS flags.
- `meta/` — console identity files (`platform`, `product_name`, `app_model`,
  `version`), bind-mounted read-only into all Go services. The image does not
  ship these files; they are the only source of console identity
  (`UOSSERVER.0000000.5.1.42.000000.000000.0000.0000`).
- `postgres/initdb.d/` — runs only on a fresh volume: trust auth, app roles
  and databases (`ulp-go`, `ulp-go-syslog`, ...).

## Known upstream bug — patched in place

`ulp-go` vendors a modified xorm whose postgres `GetColumns` template is
corrupted: the query is built from
`... c.relname = $1%s ...` by substituting the literal
`AND s.table_schema = $2` **without a leading space**, producing invalid SQL
(`c.relname = $1AND s.table_schema = $2`) that Postgres rejects with
`trailing junk after parameter`. Any `Sync2()` on an existing table then
panics the process at boot (and the 2-minute syslog cleanup ticker).

`scripts/patch-ulp-go-app.sh` fixes this with a **zero-length, in-place,
idempotent** rewrite of the single template string inside
`/usr/sbin/ulp-go-app` (drops one space elsewhere in the same string, adds it
after `$1`), preserving the binary's length and Go string metadata. It runs on
every boot from `run-ulp-go.sh` before the app starts. The resulting SQL is:

```sql
... WHERE n.nspname=s.table_schema AND c.relkind = 'r'::char
    AND c.relname = $1 AND s.table_schema = $2 AND f.attnum > 0 ...
```

Do not skip `skip_migration` or "fix" the crash by dropping tables: with the
patch, migrations and `Sync2` work correctly on both databases
(`ulp-go` and `ulp-go-syslog`).

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
