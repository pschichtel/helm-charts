# UniFi OS Server on Kubernetes (Helm chart)

A Helm chart that runs the UniFi OS Server image
(`ghcr.io/unihosted/unifi-os-server-docker`) the way its upstream Docker
Compose file does: one container running the image's own systemd and units,
unchanged. The difference: PostgreSQL, MongoDB and RabbitMQ are external
instead of inside the container. Apps can be installed and updated from the
console (InnerSpace, newer UniFi Network versions) and survive restarts. The
chart is tested against CloudNativePG, the MongoDB Community operator and the
RabbitMQ Cluster Operator.

The design goal is simple maintenance: everything the image does is left to
the image; the chart only replaces the three data services and makes systemd
work in a pod. Security hardening comes later (see "Privileged container").

This directory is the chart and also holds its development material (tests,
examples, notes); the latter is excluded from the package by `.helmignore`.
Paths below are relative to this directory; commands are run from the
repository root.

## Layout

- `templates/`, `values.yaml` — the chart.
- `files/boot.sh` — the container's entrypoint (ConfigMap, mounted at
  `/boot-script`): prepares the stock image for the external data services,
  then starts systemd. Everything the chart changes in the image is in this
  one script.
- `ci/` — values for `ct lint`.
- `test/e2e/` — kind cluster config, operator and data-service setup, chart
  values, the test script, and an optional RabbitMQ TLS overlay.
- `docs/examples/umbrella/` — an umbrella chart that installs this chart
  together with PostgreSQL (CloudNativePG), MongoDB and RabbitMQ.
- `ct.yaml` — chart-testing configuration.

## How the container is set up

`files/boot.sh` does what the upstream entrypoint (`/root/uos-entrypoint.sh`
in the image) does, minus its local MongoDB/PostgreSQL handling, then
`exec /sbin/init`:

1. Console identity: `/data/uos_uuid` and `/usr/lib/{platform,product_name,app_model,version}`
   (not in the image). The version string must have the upstream layout
   `UOSSERVER.0000000.<version>.0000000.000000.0000`: the `uos` CLI parses it,
   and with another layout `uos runnable latest-versions` fails with
   `Unsupported firmware version string`, so core cannot look up or install
   apps. The UUID is derived from the release namespace and name unless
   `console.uuid` is set, so it is stable across upgrades.
2. Masks the local `rabbitmq-server`, `epmd` and `postgresql@14-main` units.
   `postgresql.service` stays (a stub that the apps order themselves after).
3. Replaces `mongodb.service` with a no-op unit (see "Network 10.6 starts a
   MongoDB unit").
4. PostgreSQL socket proxy (see "PostgreSQL").
5. MongoDB and RabbitMQ settings of the Network app (see below).
6. Creates `/boot/.fwupdate`, so that installed apps are restored at boot
   (see "Apps").
7. Masks units that do not work in a container (see "systemd in a pod").
8. Starts upstream's log forwarder (`/root/uos-logs.cjs`) and systemd.

No unit file of the image is edited; changes are masks, new units and
drop-ins under `/etc/systemd/system`, written on every start (the container
file system is new on every start).

## External data services

### PostgreSQL: a socket proxy, and the server must trust the pod

Every app that uses PostgreSQL (core, ulp-go, uid-agent, ucs-agent,
unifi-directory, unifi-identity-update, InnerSpace, ...) connects to the
local socket `/var/run/postgresql` as a password-less role of its own name,
and its pre-start hook creates that role and its database as the superuser
`postgres` (`createuser`, `createdb`, `psql` via `runuser -u postgres`). App
packages bring these hooks with them; InnerSpace's for example hardcodes
`PGHOST=/var/run/postgresql PGUSER=unifi-innerspace PGPASSWORD=` in its unit.

Configuring each app for an external server would mean per-app work for
every app and every upgrade. Instead, `uos-postgresql-proxy.socket` listens
on `/run/postgresql/.s.PGSQL.5432` and `127.0.0.1:5432`, and
`uos-postgresql-proxy.service` (systemd's own `systemd-socket-proxyd`)
forwards both to the external server. The apps then behave exactly as on a
stock console, including apps installed later.

The price: **the external server must accept password-less connections from
the pod for every role, including the superuser `postgres`** (`trust` in
`pg_hba.conf`), like the stock image's local server. With CloudNativePG:

```yaml
spec:
  postgresql:
    pg_hba:
      - host all all all trust
```

Restrict who can reach the server with a NetworkPolicy: the umbrella example
(`docs/examples/umbrella`, `templates/postgresql/networkpolicy.yaml`) allows
only the UniFi pod, the cluster's own pods and the operator. Values:
`postgresql.host` and `postgresql.port` (from a Secret or as plain values;
CloudNativePG's `<cluster>-app` Secret has both).

#### Version 14 only

`ulp-go` (xorm fork) always emits `... c.relname = $1AND s.table_schema = $2 ...`
(no space after `$1`). PostgreSQL <= 14 accepts that; 15+ rejects it with
`trailing junk after parameter`, which panics `ulp-go` on any boot where tables
already exist. The stock image bundles PostgreSQL 14. Do not use a newer
server. (PostgreSQL 14 is end of life from November 2026; there is no fix short
of patching the binary.)

### MongoDB

The Network app gets `db.mongo.uri` and `statdb.mongo.uri` in its
`/var/lib/unifi/system.properties`. **The app keeps its own state in that
file** (`uuid`, `is_setup_completed`, `ucore.caps`,
`unifi.ucore.message_box.token`, `unifi.xmx` for the memory limit, ...), so
`boot.sh` replaces only its own keys (`db.mongo.*`, `statdb.mongo.uri`,
`rmq.*`, `system_ip`) and keeps the rest. Truncating the file (as an earlier
version of this chart did) makes the app start as a new installation on
every start: new identity, "migration to UniFi OS" on every start, and every
request mapped to a placeholder admin `factory_default`, which breaks
`PUT /proxy/network/api/self` (500, `Received invalid
ObjectId[factory_default]`) and the live-update WebSocket.

UniFi Network 10.5 uses `ace`, `ace_stat`, `ace_audit` (new; found through
`not authorized on ace_audit`) and runs `serverStatus`. The user needs
`dbOwner` on `ace`, `ace_stat`, `ace_audit` and `ace_restore`, and
`clusterMonitor` on `admin`. The database names other than `ace`/`ace_stat`
are built at runtime and do not appear as literals in the jar. Credentials
are put into the URIs URL-encoded by `files/boot.sh`.

### Network 10.6 starts a MongoDB unit

UniFi Network 10.6 runs `systemctl start unifi-mongodb`, then `mongodb`, then
`mongod` at startup (`mongoDbInstanceService`) and refuses to start if all
three fail (`systemctl start mongod failed (exit code 5)`), even with an
external `db.mongo.uri`. 10.5 does not. The unit stays in "activating" and
the app never comes up. `boot.sh` therefore replaces `mongodb.service` with
a no-op oneshot unit instead of masking it; the app then continues with the
configured external server. (10.6 also contains a MongoDB-to-PostgreSQL
migrator, `com.ubnt.db.migrator.mongo2pg`; with this setup it stays on
MongoDB.)

### RabbitMQ: Spring properties are what count

Only the Network app uses RabbitMQ. It applies `rmq.host`, `rmq.port`,
`rmq.username`, `rmq.password` from `system.properties`, but the broker
address only takes effect through Spring Boot's own `spring.rabbitmq.*`
settings. `boot.sh` writes them as `SPRING_RABBITMQ_*` variables to
`/etc/uos-chart/unifi.env`, which a drop-in
(`unifi.service.d/50-chart.conf`) adds to the unit. The same file sets
`UNIFI_MQ_CERTIFICATES_DIR=` (empty): the stock value
`/etc/rabbitmq/ssl` is for client-certificate login to the local broker.
TLS (`rabbitmq.tls`) uses `SPRING_RABBITMQ_SSL_*` with a trust store built
from the CA in a Secret.

## Apps: install, update, restore

Installing an app (InnerSpace) or updating one (UniFi Network) from the
console runs `uos runnable install`, which downloads the package to
`/data/uos/downloads` and installs it with dpkg. The image's dpkg hooks
(`/etc/dpkg/dpkg.cfg.d`) copy every UniFi package to `/persistent/dpkg/<suite>/packages`
and record the action (`unpack`, `remove`) in `.../actions`
(`/etc/default/ubnt-dpkg-cache`). On a console, `ubnt-dpkg-restore.service`
reinstalls them from there after a firmware update, if `/boot/.fwupdate`
exists. Here the root file system is new on every container start, so
`boot.sh` creates `/boot/.fwupdate` every time, and `/persistent` is on the
volume. Restoring is a local `apt-get install` from the cache (about 15 s for
Network and InnerSpace); it never downgrades: if the image brings a newer
version than the cache, the cached package is dropped.

Verified: install InnerSpace, update Network 10.5.67 to 10.6.109, uninstall
and reinstall InnerSpace; after each pod restart the installed set and
versions are as before. The app's data lives in `/data/<app>` (volume) and
its PostgreSQL database.

The API behind the console's buttons, for scripting: `POST
/api/controllers/<name>/install`, `POST /api/controllers/checkUpdates` and
then `POST /api/controllers/<name>/update` (without a prior check, update
answers 204 and does nothing), `POST /api/controllers/<name>/uninstall`.

## Volumes

One PVC, mounted in parts (`subPath`): `/data` (`data`), `/var/lib/unifi`
(`unifi-var-lib`), `/srv` (`srv`) and `/persistent` (`persistent`). Memory
backed (tmpfs) as in the upstream compose file: `/run`, `/run/lock`, `/tmp`,
`/var/log/journal`, `/var/opt/unifi/tmp` and `/data/unifi-core/config/http`
(nginx snippets that core generates at every start).

## systemd in a pod

### Privileged container

systemd needs a writable cgroup tree. The upstream compose file bind-mounts
the host's `/sys/fs/cgroup` writable with `cgroup: host`; in Kubernetes the
simple equivalent is `securityContext.privileged: true` (the default here).
In a user namespace (`hostUsers: false`) that does not work: the writable
cgroup tree then belongs to the host's root, which is not mapped
(`Failed to create .../init.scope control group: Permission denied`).
[KEP-5474](https://www.kubernetes.dev/resources/keps/5474/)
(`securityContext.cgroupOptions.mountMode: ReadWrite`, alpha in 1.38) is the
way out: with a private cgroup namespace and a user namespace, runc hands the
container's cgroup to the container's root (runc's
`tests/integration/cgroup_delegation.bats`). Once it is available in the
runtime, `privileged` can be replaced by `hostUsers: false` plus that
setting.

### Units that do not work here

A privileged container sees the node's devices and kernel log. Masked or
changed by `boot.sh`:

- `getty@.service`, `serial-getty@.service`: the getty generator finds the
  node's consoles (`/dev/hvc0`), and systemd waits 90 s for their devices
  (no udev in the container) before it starts anything.
- `/tmp` must be a tmpfs: a disk-backed `emptyDir` is a mount of the node's
  disk (`/dev/vda`), and `tmp.mount` then waits 90 s for that device.
- `systemd-sysctl.service`: cannot set kernel parameters.
- journald `ReadKMsg=no`: the node's kernel log (audit messages of every
  container) would end up in the journal.

### Stop, restart, reboot

The image's `STOPSIGNAL` is `SIGRTMIN+3` (systemd's "halt"), which containerd
sends on pod deletion: systemd stops all units in order (about 2 s). A reboot
from the console (`POST /api/system/reboot`) ends systemd; the kubelet
restarts the container (one container restart, exit code 129), and the
console is back after about 40 s. Restarts of single services
(`systemctl restart unifi`, e.g. after changing the Network memory limit) are
done by systemd itself.

### Time zone

Core sets the zone with `ubnt-systool timezone` (`/etc/localtime`,
`/etc/timezone`, `systemctl restart cron`) on setup and again 8 s after
every start from its database, so nothing needs to be persisted. Do not set
`TZ` in the container's environment: it would override the zone chosen in the
console.

## Logging

Upstream's forwarder (`/root/uos-logs.cjs`) follows the journal of the UniFi
units (`unifi*`, `uos*`, `ulp*`, `ucs*`, `uid-agent`, `nginx`, `postgresql`,
`mongodb`) and writes them to the container log as
`<time> [<service>] <LEVEL>: <message>` (`UOS_LOG_FORMAT=json` for JSON).
What the apps write only to their own files is not forwarded: core's
`/data/unifi-core/logs/*.log` and the Network app's
`/data/unifi/logs/server.log`.

## Testing

`test/e2e/setup.sh` creates a kind cluster with cert-manager, CloudNativePG,
mongodb-kubernetes and the RabbitMQ Cluster Operator plus the data services;
`test/e2e/run.sh` installs the chart and checks readiness without restarts,
runs `helm test`, and waits for the setup wizard in a headless browser. See
[test/e2e/README.md](test/e2e/README.md) for the manual checks (apps,
settings, restarts).

Static checks: `ct lint --config charts/unifi-os-server/ct.yaml` and
`helm template ... | kubeconform -strict`.

## Services

Two Services, so that the web side and the device side can be exposed
differently (`service.web`, `service.device`; each has `type`, `annotations`,
`loadBalancerSourceRanges`, `externalTrafficPolicy` and
`ports`):

- `<fullname>` (web): `http` 80 and `https` 443, the UI. The ingress points
  here. `ClusterIP` by default.
- `<fullname>-device`: `inform` 8080, `stun` 3478/UDP, `speedtest` 6789 and
  the optional guest portal ports `portal-http` 8880 and `portal-https` 8843.
  `ClusterIP` by default; typically a `LoadBalancer` with
  `externalTrafficPolicy: Local`, so that devices keep their source address.
  Mixed TCP/UDP on one LoadBalancer needs Kubernetes 1.26.

Both Services can share one IP with the controller's own mechanism (MetalLB
`metallb.universe.tf/allow-shared-ip`, Cilium `lbipam.cilium.io/sharing-key`
in `annotations`), but then the web ports are reachable on it as well if the
web Service is a LoadBalancer too.

## Ingress and reverse proxies

The UI is HTTPS-only (port 80 redirects to 443, self-signed certificate), so
an ingress should talk HTTPS to the `https` port of the web Service
(`ingress.servicePort: https`, the default) without verifying the backend
certificate. The UI depends on WebSockets (`/api/ws/system`,
`/proxy/network/wss/...`).

**The proxy must talk HTTP/1.1 to the backend.** The pod's nginx offers
HTTP/2 via ALPN but cannot carry WebSockets over HTTP/2 (RFC 8441). A proxy
that negotiates HTTP/2 to the backend makes every WebSocket fail; the browser
shows `net::ERR_HTTP2_SERVER_REFUSED_STREAM` and the console stays empty or
half-loaded after login. Browsers may use HTTP/2 to the proxy itself.

HAProxy Kubernetes Ingress (haproxytech), verified with chart 1.56.4:
`server-ssl` alone generates `ssl alpn h2,http/1.1`; `server-proto: h1`
removes the ALPN:

```yaml
ingress:
  enabled: true
  className: haproxy
  annotations:
    haproxy.org/server-ssl: "true"
    haproxy.org/server-proto: "h1"
```

ingress-nginx talks HTTP/1.1 to backends anyway
(`nginx.ingress.kubernetes.io/backend-protocol: HTTPS`).

## Pod hostname

By default the pod's hostname is its name, which changes whenever the pod is
recreated. `podHostname` sets a fixed one (`spec.hostname`). Whether the image's
services use the hostname (for example as the console name) has not been
verified.

## Upgrading from 0.3 (one container per service)

Not automatic. The volume layout changed (0.3 mounted one subdirectory per
service under `/data`, now `/data` is one `subPath`), and 0.3 used
pre-created PostgreSQL roles with passwords and configurable database names,
whereas the apps now create their own with the stock names. Back up from the
console and restore into a new installation.

## Known gaps

- The setup wizard is verified to complete with a local account ("Proceed
  Without a UI Account"), not with a UI account, and device adoption is not
  verified.
- `uos-discovery-client` runs but cannot see the LAN from a pod network
  (layer-2 discovery). Devices must be adopted via `set-inform`, DHCP option
  43 or DNS.
- `console.systemIP` (`system_ip`) is passed to the Network app; its effect on
  the inform address has not been verified with a real device.
- `GET /proxy/network/v2/api/site/default/shadowmode/managed/group` answers
  400 `api.err.SiteGatewayNotFound` on a site without a UniFi gateway (seen
  on the e2e setup, which has no devices); behaviour with a gateway is not
  verified.
- Core's and the Network app's file logs are not in the container log (see
  Logging).
