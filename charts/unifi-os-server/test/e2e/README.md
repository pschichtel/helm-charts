# End-to-end test

Runs the chart against real operator-managed data services in a local kind
cluster.

```console
charts/unifi-os-server/test/e2e/setup.sh   # kind cluster, cert-manager, CloudNativePG, mongodb-kubernetes,
                                           # RabbitMQ Cluster Operator, PostgreSQL/MongoDB/RabbitMQ instances
charts/unifi-os-server/test/e2e/run.sh     # install the chart, check readiness and zero restarts,
                                           # helm test, setup wizard in headless chromium (if installed)
```

PostgreSQL databases and roles are provisioned by CloudNativePG alone by
default. With `POSTGRES_PROVISIONER=db-operator` (set for both scripts),
`setup.sh` also installs db-operator and lets it create them, and `run.sh`
adds `values-db-operator.yaml`. To switch an existing setup, clean up the
namespace first (see below).

Requirements: docker, kind, kubectl, helm; chromium for the browser check.
`setup.sh` imports the UniFi OS image from the local docker daemon if
present (otherwise the node pulls it, ~2.8 GB). The whole test needs about
5 GB of RAM.

Files:

- `kind.yaml` — single-node cluster, kube-proxy in nftables mode.
- `data-services.yaml` — MongoDB and RabbitMQ as operator resources
  (namespace `unifi`): a `MongoDBCommunity` replica set with the roles the
  Network app needs, and a `RabbitmqCluster`.
- `postgres-cnpg.yaml` — a CloudNativePG `Cluster` (PostgreSQL 14) with the
  four fixed-name roles of the Go services as managed roles and one
  CloudNativePG `Database` per service.
- `postgres-db-operator.yaml` — the same server with superuser access, a
  db-operator `DbInstance` and one db-operator `Database` per database. The
  Secrets of the Go services are created up front, because db-operator would
  otherwise generate user names (see the repository README).
- `values.yaml` — chart values pointing at those services and their
  operator-generated secrets; `values-db-operator.yaml` overrides the
  PostgreSQL credentials for the db-operator variant.
- `rabbitmq-tls.yaml`, `values-rabbitmq-tls.yaml` — optional: TLS for
  RabbitMQ via cert-manager. Apply the first, then
  `helm upgrade uos charts/unifi-os-server -n unifi -f charts/unifi-os-server/test/e2e/values.yaml -f charts/unifi-os-server/test/e2e/values-rabbitmq-tls.yaml`.

Operator versions are pinned at the top of `setup.sh`. The MongoDB operator
is `mongodb-kubernetes`, the successor of the deprecated `community-operator`
chart; it serves the same `MongoDBCommunity` resource.

## Pitfalls seen while building this

- **mongodb-kubernetes with a cluster-wide watch** creates the service account
  of the replica set pods (`mongodb-kubernetes-appdb`) only in its own
  namespace. Without it in the target namespace the StatefulSet cannot create
  pods, and it backs off for a long time; after adding the account, delete
  the StatefulSet so the operator recreates it.
- **The RabbitMQ Cluster Operator (2.x)** uses an admission webhook whose
  certificate comes from cert-manager. Install cert-manager first, otherwise
  the operator pod waits forever for `cluster-operator-webhook-server-cert`.
- **db-operator 2.44** serves `DbInstance` only as `kinda.rocks/v1beta1`,
  where the admin secret reference has capitalised fields
  (`adminSecretRef: {Namespace, Name}`). Its docs on the main branch already
  show `v1`.
- **Webhooks refuse connections** for a few seconds after their pods are
  ready; `setup.sh` retries applies.
- **`kind load docker-image`** fails for the multi-platform UniFi OS image
  when only one platform is present locally (`ctr: content digest ... not
  found`, it imports with `--all-platforms`); `setup.sh` pipes `docker save`
  into `ctr import --platform linux/amd64` instead.

Only relevant on unusual hosts (seen in a small VM):

- **Kernels without `xt_statistic` and `nft_numgen`**: kube-proxy cannot
  balance a Service over several endpoints in either iptables or nftables
  mode, and one such rule fails the whole sync, so no Service works
  (webhooks time out, DNS fails). `setup.sh` runs CoreDNS with one replica,
  which leaves no multi-endpoint Service in the test cluster. That is enough
  in iptables mode only: nftables mode uses `numgen` for single-endpoint
  Services too (`numgen random mod 1`), so even the `kubernetes` Service
  fails and CoreDNS never becomes ready. On such a kernel, create the cluster
  yourself from a copy of `kind.yaml` with `kubeProxyMode: iptables` before
  running `setup.sh` (it reuses an existing cluster).
- **Low `kernel.pid_max`** (e.g. 8192): docker and systemd derive task limits
  from it (15% per level), which left each container with 184 tasks, too few
  for UniFi OS core's 256 libuv threads (`Aborted`, exit 134). Raise
  `pid_max` before creating the cluster, or lift the limits of the running
  node: write `max` to the node container's `pids.max` on the host and set
  `DefaultTasksMax=infinity` in the node's systemd, or lower
  `containers.unifiCore.uvThreadpoolSize`.

## Cleanup

```console
helm uninstall uos -n unifi
kubectl delete pvc -n unifi uos-unifi-os-server-data     # kept on uninstall by default
kubectl delete -n unifi databases.kinda.rocks --all      # db-operator variant only
kubectl delete dbinstances.kinda.rocks unifi-pg          # db-operator variant only (cluster-scoped)
kubectl delete -n unifi databases.postgresql.cnpg.io,clusters.postgresql.cnpg.io,mongodbcommunity,rabbitmqclusters.rabbitmq.com --all   # operator resources first ...
kubectl delete namespace unifi                           # ... then the namespace
kind delete cluster --name uos-e2e                       # or everything at once
```

Deleting the namespace while the operator resources still exist can leave it
in `Terminating` (seen here: the resources never got a deletion timestamp);
deleting them explicitly first avoids that.
