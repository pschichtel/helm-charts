#!/usr/bin/env bash
# Creates a kind cluster with the three operators and the external data
# services the chart expects (PostgreSQL, MongoDB, RabbitMQ).
#   charts/unifi-os-server/test/e2e/setup.sh
# An existing cluster is reused.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=uos-e2e
IMAGE=${IMAGE:-ghcr.io/unihosted/unifi-os-server-docker:5.1.42}
CNPG_CHART_VERSION=0.29.1          # CloudNativePG operator 1.30.1
MCK_CHART_VERSION=1.15.0           # mongodb-kubernetes (successor of the community-operator chart)
RABBITMQ_OPERATOR_VERSION=v2.23.3  # RabbitMQ Cluster Operator
CERT_MANAGER_VERSION=v1.21.3       # required by the RabbitMQ operator's webhooks

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config kind.yaml --wait 180s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

# Some VM kernels lack both xt_statistic and nft_numgen, which kube-proxy
# (iptables resp. nftables mode) needs to balance a Service across several
# endpoints. One such rule makes the whole sync fail, so no Service works.
# CoreDNS is the only multi-endpoint Service in this test cluster; run it
# with one replica. Harmless on kernels that have the modules.
kubectl -n kube-system scale deploy/coredns --replicas=1
kubectl -n kube-system rollout status deploy/coredns --timeout=120s

# The image is large (~2.8 GB); import it from the local docker daemon if
# present, otherwise the node pulls it. Imported with ctr directly because
# `kind load` uses --all-platforms, which fails for a multi-platform image of
# which only one platform is present locally ("content digest ... not found").
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker save "$IMAGE" | docker exec -i "$CLUSTER-control-plane" \
    ctr --namespace=k8s.io images import --platform linux/amd64 --digests --snapshotter=overlayfs -
fi

helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
helm repo add mongodb https://mongodb.github.io/helm-charts >/dev/null
helm repo update cnpg mongodb >/dev/null

helm upgrade --install cnpg cnpg/cloudnative-pg --version "$CNPG_CHART_VERSION" \
  -n cnpg-system --create-namespace --wait --timeout 5m
helm upgrade --install mck mongodb/mongodb-kubernetes --version "$MCK_CHART_VERSION" \
  -n mongodb --create-namespace --set operator.watchNamespace='*' --wait --timeout 5m
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml"
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s

# Webhooks can refuse connections for a few seconds after their pods report
# ready; retry applies instead of failing.
retry_apply() {
  local _
  for _ in $(seq 1 30); do
    kubectl apply "$@" && return 0
    sleep 5
  done
  return 1
}
retry_apply -f "https://github.com/rabbitmq/cluster-operator/releases/download/$RABBITMQ_OPERATOR_VERSION/cluster-operator.yml"
kubectl -n rabbitmq-system rollout status deploy/rabbitmq-cluster-operator --timeout=300s

retry_apply -f data-services.yaml
retry_apply -f postgres-cnpg.yaml

echo "waiting for the data services..."
kubectl -n unifi wait cluster.postgresql.cnpg.io/unifi-pg --for=condition=Ready --timeout=600s
kubectl -n unifi get secret unifi-pg-app
kubectl -n unifi wait mongodbcommunity/unifi-mongo --for=jsonpath='{.status.phase}'=Running --timeout=900s
kubectl -n unifi wait rabbitmqcluster/unifi-rmq --for=condition=AllReplicasReady --timeout=600s
kubectl -n unifi get secret unifi-mongo-admin-unifi unifi-rmq-default-user
