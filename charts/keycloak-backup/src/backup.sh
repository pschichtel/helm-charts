#!/usr/bin/env bash

set -euo pipefail

echo "Preparing backup..."

script_path="${SCRIPT_PATH?no script path configured!}"
namespace="$(cat "/var/run/secrets/kubernetes.io/serviceaccount/namespace")"
keycloak="keycloaks.k8s.keycloak.org/${KEYCLOAK?no keycloak configured!}"
pod="${BACKUP_POD_NAME?no pod name configured}"
pvc="${BACKUP_PVC_NAME?no pvc name configured}"
volume="${VOLUME?no volume configured!}"
node_name="${NODE_NAME?no NODE_NAME configured!}"


keycloak_object="$(kubectl -n "$namespace" get -o json "$keycloak")"
jq_transformer="$script_path/transform.jq"
overrides="$(jq -rMc --arg name "$pod" --arg pvc "$pvc" --arg volumeAt "$volume" --arg node "$node_name" -f "$jq_transformer" <<< "$keycloak_object")"
optimized="$(jq -rMc '.spec.startOptimized // true' <<< "$keycloak_object")"

export_cmd=(export --dir "$volume" --users realm_file)
if [ "$optimized" = 'true' ]
then
  export_cmd+=(--optimized)
fi

if [ -n "${KC_USERS_PER_FILE:-}" ]
then
  export_cmd+=(--users "$KC_USERS")
fi

if [ -n "${KC_USERS_PER_FILE:-}" ]
then
  export_cmd+=(--users-per-file "$KC_USERS_PER_FILE")
fi

echo "Overrides:"
jq <<< "$overrides"
echo "Export command:"
echo "$ ${export_cmd[*]}"
echo ""

echo "Starting backup..."
find "$volume" -mindepth 1 -depth -delete
kubectl -n "$namespace" delete --ignore-not-found "pod/$pod"
kubectl -n "$namespace" run \
  --rm \
  --attach \
  --restart=Never \
  --image="dummy" \
  --override-type=strategic \
  --overrides="$overrides" \
  "$pod" \
  -- \
  "${export_cmd[@]}"
find "$volume" -mindepth 1
echo "Backup complete!"