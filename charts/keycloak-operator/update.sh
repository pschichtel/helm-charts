#!/usr/bin/env bash

version="25.0.5"

curl -sLfo templates/kubernetes.yml "https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${version}/kubernetes/kubernetes.yml"

