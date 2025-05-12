#!/usr/bin/env bash

version="$(yq .appVersion Chart.yaml)"

cd templates
rm -v *

file='kubernetes.yml'

remove_noise() {
    yq -i "del(${1:-}.metadata.labels[\"app.kubernetes.io/managed-by\"]) | del(${1:-}.metadata.annotations[\"app.quarkus.io/build-timestamp\"])" "$file"
}

curl -sLf -o "$file" "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${version}/kubernetes/kubernetes.yml"
remove_noise
remove_noise ".spec.template"
sed -i -r 's/ClusterRole(Binding)?/Role\1/g' "$file"
sed -i -r "s/$version/{{ .Chart.AppVersion }}/g" "$file"
sed -i -r 's/image:.+/image: {{ print .Values.image.repository ":" (.Values.image.tag | default .Chart.AppVersion) | quote }}/g' "$file"
sed -i -r 's/imagePullPolicy:.+/imagePullPolicy: {{ .Values.image.pullPolicy }}/g' "$file"
