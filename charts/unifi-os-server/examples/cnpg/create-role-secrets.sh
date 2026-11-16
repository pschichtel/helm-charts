#!/usr/bin/env bash
# Creates the password Secrets of the four fixed-name PostgreSQL roles with
# random passwords. Existing Secrets are left alone, so it is safe to re-run.
#   charts/unifi-os-server/examples/cnpg/create-role-secrets.sh <namespace>
#
# The passwords are hex: the Go services insert them unquoted into their
# connection strings and config files, so whitespace, quotes, backslashes
# and "$" are not allowed.
set -euo pipefail
ns=${1:?usage: $0 <namespace>}

for role in ulp-go uid ucs-agent unifi-directory; do
  name=unifi-pg-$role
  if kubectl -n "$ns" get secret "$name" >/dev/null 2>&1; then
    echo "secret/$name exists, kept"
    continue
  fi
  kubectl -n "$ns" create secret generic "$name" --type=kubernetes.io/basic-auth \
    --from-literal=username="$role" \
    --from-literal=password="$(openssl rand -hex 24)"
  # Let CloudNativePG pick up password changes in the Secret.
  kubectl -n "$ns" label secret "$name" cnpg.io/reload=true
done
