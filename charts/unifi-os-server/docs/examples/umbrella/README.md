# Umbrella chart: UniFi OS Server with its data services

Installs the `unifi-os-server` chart together with everything it needs, using
three operators that must already be running in the cluster:

| Template | Resources | Operator |
|---|---|---|
| `templates/postgresql/` | `Cluster` `unifi-pg` (PostgreSQL 14) that trusts every connection | [CloudNativePG](https://cloudnative-pg.io) |
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

- **The MongoDB password** is generated at install time (`randAlphaNum`) and
  kept on upgrade by looking up the existing Secret. This needs a live
  cluster: `helm template`, `--dry-run` without server access and GitOps
  tools that render offline (e.g. Argo CD) generate a new one on every
  render. In that case create the Secret `unifi-mongo-password` (key
  `password`) yourself and drop it from the templates.
- **Fixed names** (`unifi-pg`, `unifi-mongo`, `unifi-rmq`): subchart values
  cannot be templated, so the Secret names in `values.yaml` cannot follow the
  release name. Install one stack per namespace.
- **MongoDB RBAC**: `mongodb-kubernetes` creates the service account of its
  replica set pods only in the operator's namespace. Set
  `mongodb.createAppdbRbac: false` if the operator runs in the release
  namespace.
- **PostgreSQL 14**, pinned: `ulp-go` sends SQL that 15+ rejects.
- **PostgreSQL trusts every connection** (`pg_hba: host all all all trust`):
  the UniFi apps connect without a password and create their own roles and
  databases as `postgres`, as on a stock console.
- **NetworkPolicy** `unifi-pg` (`templates/postgresql/networkpolicy.yaml`,
  `cnpg.networkPolicy`) makes that trust safe: only the UniFi pod connects to
  port 5432; the cluster's own pods talk to each other (replication); the
  operator reaches the instances' status port 8000. Outgoing traffic is limited
  to the cluster's own pods, DNS and the Kubernetes API (ports 443 and 6443;
  narrow `apiServerCIDRs` to the API server's addresses). Set
  `cnpg.networkPolicy.operatorNamespace` if the operator is not in
  `cnpg-system`; add metrics scraping or backup targets with `extraIngress`
  and `extraEgress`. The policy needs a CNI that enforces NetworkPolicy.
- The pod may start before the databases are ready and restart a few times
  until they are.

Backups (e.g. the Barman Cloud plugin), monitoring and resource limits are
left out; add them as for any CloudNativePG, MongoDB or RabbitMQ setup.
