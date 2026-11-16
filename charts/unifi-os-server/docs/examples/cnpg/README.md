# PostgreSQL with CloudNativePG

Manifests for a dedicated PostgreSQL 14 cluster that the `unifi-os-server`
chart can use, run by [CloudNativePG](https://cloudnative-pg.io) alone.

| File | Contents |
|---|---|
| `cluster.yaml` | `Cluster` `unifi-pg`: PostgreSQL 14, 3 instances, the bootstrap database `unifi-core` (owner `unifi-core`, Secret `unifi-pg-app`), and the four fixed-name roles of the Go services as managed roles |
| `databases.yaml` | one `Database` per Go service database, owned by its role (`ulp-go`, `ulp-go-syslog`, `uid`, `ucs-agent`, `unifi-directory`) |
| `create-role-secrets.sh` | creates the password Secrets of the four roles (random, hex); keeps existing ones |
| `kustomization.yaml` | the two manifests above, without a namespace |
| `values.yaml` | the chart's `postgresql` values for this cluster |

Requirements: CloudNativePG 1.25 or newer (for `Database` resources); the
example was tested with 1.30.

## Usage

Everything goes into the namespace the chart is installed in:

```console
charts/unifi-os-server/docs/examples/cnpg/create-role-secrets.sh unifi
kubectl apply -k charts/unifi-os-server/docs/examples/cnpg -n unifi
kubectl -n unifi wait cluster.postgresql.cnpg.io/unifi-pg --for=condition=Ready --timeout=10m
helm install uos charts/unifi-os-server -n unifi -f charts/unifi-os-server/docs/examples/cnpg/values.yaml -f my-values.yaml
```

`my-values.yaml` holds the MongoDB and RabbitMQ settings (and anything else).
If you manage Secrets with a secret manager instead of the script, create
`unifi-pg-<role>` Secrets with the keys `username` (exactly the role name)
and `password`, optionally labelled `cnpg.io/reload: "true"`.

## Why it looks like this

- **PostgreSQL 14**, pinned: `ulp-go` sends SQL that 15+ rejects. Do not let
  the image float to a newer major version.
- **Fixed role names** `ulp-go`, `uid`, `ucs-agent`, `unifi-directory`: the Go
  services' schema migrations, which are SQL files in the image, contain
  `OWNER TO "<role>"`. Their database names are free, as long as
  `databases.yaml` and the chart values agree.
- **Passwords**: the Go services put them unquoted into their connection
  strings; whitespace, quotes, backslashes and `$` are rejected. The script
  generates hex.
- **Host and port** of the Go services come from `unifi-pg-app`: role Secrets
  only contain `username` and `password`, and every field of
  `postgresql.auth.<service>` can come from a different Secret.
- **`ulp-go-syslog`**: `ulp-go`'s second database (its activity log), same
  user.
- **No TLS** to PostgreSQL: the Go services hardcode `sslmode=disable`. The
  default CloudNativePG setup accepts unencrypted connections from the pod
  network.
- `databaseReclaimPolicy: retain`: deleting a `Database` resource leaves the
  database in PostgreSQL.

Backups (e.g. the Barman Cloud plugin), monitoring and resource limits are
left out; add them as for any CloudNativePG cluster.
