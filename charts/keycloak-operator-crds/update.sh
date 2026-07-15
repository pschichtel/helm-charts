#!/usr/bin/env bash

version="$(yq .appVersion Chart.yaml)"

cd templates
rm -v *

files=(
  keycloakoidcclients.k8s.keycloak.org-v1.yml
  keycloakrealmimports.k8s.keycloak.org-v1.yml
  keycloaks.k8s.keycloak.org-v1.yml
  keycloaksamlclients.k8s.keycloak.org-v1.yml
)

for file in "${files[@]}"
do
  curl -sLOf "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${version}/kubernetes/$file"
done

