# Umbrella chart: UniFi OS Server with its data services

Installs the `unifi-os-server` chart together with everything it needs, using
three operators that must already be running in the cluster:

| Template | Resources | Operator |
|---|---|---|
| `templates/postgresql/` | `Cluster` `unifi-pg` (PostgreSQL 14), the four fixed-name roles as `DatabaseRole`s with generated password Secrets, one `Database` per service, one file each | [CloudNativePG](https://cloudnative-pg.io) 1.30+ (`DatabaseRole`) |
| `templates/mongodb.yaml` | `MongoDBCommunity` `unifi-mongo`, generated password Secret, the operator's pod service account | MongoDB Community (`mongodb-kubernetes`) |
| `templates/rabbitmq.yaml` | `RabbitmqCluster` `unifi-rmq` | RabbitMQ Cluster Operator |

`values.yaml` wires the subchart to the Secrets the operators create, so a
basic setup needs no values at all:

```console
helm dependency build charts/unifi-os-server/docs/examples/umbrella
helm install uos charts/unifi-os-server/docs/examples/umbrella -n unifi --create-namespace
```

Settings of the data services (instances, storage, MongoDB version) are in
`values.yaml`; chart settings such as `console.systemIP`, `service` or
`ingress` go under `unifi-os-server:`. The chart has separate Services for the
UI and for devices (`service.web`, `service.device`); `values.yaml` has the
usual setup as a commented example: a LoadBalancer for the device ports, the
UI behind an ingress. In your own umbrella, replace
`repository: file://../../..` in `Chart.yaml` with the repository the chart is
published to.

## Notes

- **Passwords** are generated at install time (`randAlphaNum`, alphanumeric
  because the Go services put them unquoted into connection strings) and kept
  on upgrade by looking up the existing Secret. This needs a live cluster:
  `helm template`, `--dry-run` without server access and GitOps tools that
  render offline (e.g. Argo CD) generate new ones on every render. In that
  case create the Secrets `unifi-pg-<role>` and `unifi-mongo-password` (key
  `password`) yourself and drop them from the templates.
- **Fixed names** (`unifi-pg`, `unifi-mongo`, `unifi-rmq`): subchart values
  cannot be templated, so the Secret names in `values.yaml` cannot follow the
  release name. Install one stack per namespace.
- **MongoDB RBAC**: `mongodb-kubernetes` creates the service account of its
  replica set pods only in the operator's namespace. Set
  `mongodb.createAppdbRbac: false` if the operator runs in the release
  namespace.
- **PostgreSQL 14**, pinned: `ulp-go` sends SQL that 15+ rejects. The four
  roles `ulp-go`, `uid`, `ucs-agent`, `unifi-directory` have fixed names because
  the Go services' schema migrations contain `OWNER TO "<role>"`.
- **No TLS** to PostgreSQL: the Go services hardcode `sslmode=disable`.
- `databaseReclaimPolicy: retain`: uninstalling leaves the databases in
  PostgreSQL (and the Cluster's volumes, per CloudNativePG).
- The pod may start before the databases are ready and restart a few times
  until they are.

Backups (e.g. the Barman Cloud plugin), monitoring and resource limits are
left out; add them as for any CloudNativePG, MongoDB or RabbitMQ setup.
