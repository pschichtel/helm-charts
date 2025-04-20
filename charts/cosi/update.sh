#!/usr/bin/env bash

appVersion="$(yq -r .appVersion Chart.yaml)"
tag="v$appVersion"

templates_dir="$PWD/templates"
crd_chart_dir="$PWD/charts/crds"
crd_chart_templates_dir="$crd_chart_dir/templates"

rm -R "$templates_dir" "$crd_chart_dir"
git_repo_dir="$(mktemp -d)"
git clone --depth=1 -b "$tag" https://github.com/kubernetes-sigs/container-object-storage-interface.git "$git_repo_dir"
echo "Tag: $tag"

mkdir -p "$templates_dir" "$crd_chart_templates_dir"
kubectl kustomize -o "$templates_dir" "$git_repo_dir"

rm -v "$templates_dir"/v1_namespace_*.yaml
mv -v "$templates_dir"/*customresourcedefinition*.yaml "$crd_chart_templates_dir"
find "$templates_dir" -type f -name '*.yaml' -exec yq eval -i 'del(.metadata.namespace) | del(.metadata.labels["app.kubernetes.io/managed-by"])' "{}" \;
find "$templates_dir" -type f \( -name 'rbac.authorization.k8s.io_v1_rolebinding_*.yaml' -o -name 'rbac.authorization.k8s.io_v1_clusterrolebinding_*.yaml' \) -exec yq eval -i '.subjects = (.subjects | map(.namespace = "{{ .Release.Namespace }}"))' "{}" \;

cat <<EOL > "$crd_chart_dir/Chart.yaml"
apiVersion: v2
name: crds

type: application
version: "$appVersion"
appVersion: "$appVersion"
EOL