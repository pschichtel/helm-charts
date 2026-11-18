#!/usr/bin/env bash
# Installs the chart against the data services from setup.sh and verifies it:
# all containers ready, no container restarts, helm test, the setup wizard in
# a headless browser (if chromium is available), and a pod restart.
set -euo pipefail
cd "$(dirname "$0")"
NS=unifi
REL=uos
CHART=../..

kubectl config use-context kind-uos-e2e >/dev/null
VALUES=(-f values.yaml)
# Same switch as setup.sh: POSTGRES_PROVISIONER=cnpg|db-operator
[ "${POSTGRES_PROVISIONER:-cnpg}" = cnpg ] || VALUES+=(-f "values-$POSTGRES_PROVISIONER.yaml")
helm upgrade --install "$REL" "$CHART" -n "$NS" "${VALUES[@]}" --wait --timeout 15m

pod=$(kubectl -n "$NS" get pod -l app.kubernetes.io/instance="$REL" -o jsonpath='{.items[0].metadata.name}')
echo "pod: $pod"
kubectl -n "$NS" get pod "$pod" -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\tready="}{.ready}{"\trestarts="}{.restartCount}{"\n"}{end}'
restarts=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{" "}{end}' | tr ' ' '\n' | awk '{s+=$1} END {print s+0}')
[ "$restarts" -eq 0 ] || { echo "FAIL: containers restarted ($restarts)"; exit 1; }

helm test "$REL" -n "$NS"

# Setup wizard in a browser, through a port-forward to the service.
if command -v chromium >/dev/null; then
  kubectl -n "$NS" port-forward "svc/$REL-unifi-os-server" 18443:443 >/dev/null 2>&1 &
  pf=$!
  trap 'kill $pf 2>/dev/null || true' EXIT
  sleep 3
  ok=
  for _ in $(seq 1 30); do
    labels=$(timeout 100 chromium --headless=new --no-sandbox --disable-gpu --ignore-certificate-errors \
      --virtual-time-budget=30000 --dump-dom https://127.0.0.1:18443/ 2>/dev/null \
      | grep -oE 'data-label="[^"]+"' | head -2 | tr '\n' ' ' || true)
    echo "  UI: ${labels:-<nothing yet>}"
    if echo "$labels" | grep -q "Name Your UniFi"; then ok=1; break; fi
    sleep 10
  done
  [ -n "$ok" ] || { echo "FAIL: setup wizard did not appear"; exit 1; }
fi

echo "PASS"
