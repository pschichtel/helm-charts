#!/usr/bin/env bash

version="$(yq .appVersion Chart.yaml)"

file='kubernetes.yml'

sed -i -r 's/ClusterRole(Binding)?/Role\1/g' "$file"
sed -i -r "s/$version/{{ .Chart.AppVersion }}/g" "$file"
sed -i -r 's/namespace: keycloak/namespace: {{ .Release.Namespace }}/g' "$file"
