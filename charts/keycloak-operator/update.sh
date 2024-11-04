#!/usr/bin/env bash

version="$(yq .appVersion Chart.yaml)"

cd templates
rm -v *

curl -sLOf "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${version}/kubernetes/kubernetes.yml"

