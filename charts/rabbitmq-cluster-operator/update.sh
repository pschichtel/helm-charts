#!/usr/bin/env bash

set -euo pipefail

version="$(yq .appVersion Chart.yaml)"

mkdir -p templates/generated
cd templates/generated
find -mindepth 1 -delete

file='kubernetes.yml'

echo "Updating to $version"
curl -sLf -o "$file" "https://github.com/rabbitmq/cluster-operator/releases/download/v${version}/cluster-operator-ghcr-io.yml"
yq -s '(.kind | downcase) + "_" + .metadata.name + ".yml"' "$file"
rm -v "$file"
rm -v namespace_*.yml

export RESOURCE_NAME='{{ include "rabbitmq-cluster-operator.name" $ }}'
export RESOURCE_FULLNAME='{{ include "rabbitmq-cluster-operator.fullname" $ }}'
export NAME_PREFIX='^(cluster-operator|rabbitmq-cluster-operator|rabbitmq-cluster)'
export IMAGE='{{ print .Values.image.registry "/" .Values.image.repository ":" (.Values.image.tag | default .Chart.AppVersion) }}'

for f in *.yml
do
    kind="$(yq '.kind | downcase' "$f")"
    name="$(yq '.metadata.name' "$f")"
    echo "Processing kind: $kind"

    # these match names and thus need to happen before renaming
    if [ "$kind" = "certificate" ] && [ "$name" = "cluster-operator-serving-cert" ]
    then
        yq -i '.spec.dnsNames |= [ strenv(RESOURCE_FULLNAME) + "-webhook-service.{{ .Release.Namespace }}.svc", strenv(RESOURCE_FULLNAME) + "-webhook-service.{{ .Release.Namespace }}.svc.{{ .Values.clusterDomain }}" ]' "$f"
    fi
    if [ "$kind" = "certificate" ] && [ "$name" = "metrics-certs" ]
    then
        yq -i '.metadata.name = strenv(RESOURCE_FULLNAME) + "-metrics-certs"' "$f"
        yq -i '.spec.dnsNames |= [ strenv(RESOURCE_FULLNAME) + "-metrics-certs.{{ .Release.Namespace }}.svc", strenv(RESOURCE_FULLNAME) + "-metrics-certs.{{ .Release.Namespace }}.svc.{{ .Values.clusterDomain }}" ]' "$f"
    fi

    yq -i 'del(.metadata.namespace)' "$f"
    yq -i '.metadata.name |= sub(strenv(NAME_PREFIX), strenv(RESOURCE_FULLNAME))' "$f"
    yq -i '.metadata.labels["app.kubernetes.io/name"]     = strenv(RESOURCE_NAME)' "$f"
    yq -i '.metadata.labels["app.kubernetes.io/instance"] = "{{ .Release.Name }}"' "$f"
    if [ "$kind" = 'clusterrolebinding' ] || [ "$kind" = "rolebinding" ]
    then
        yq -i '.roleRef.name |= sub(strenv(NAME_PREFIX), strenv(RESOURCE_FULLNAME)) | .subjects = (.subjects | map(.namespace = "{{ .Release.Namespace }}" | .name |= sub(strenv(NAME_PREFIX), strenv(RESOURCE_FULLNAME))))' "$f"
    fi
    if [ "$kind" = 'deployment' ]
    then
        yq -i '.spec.selector.matchLabels["app.kubernetes.io/name"]         = strenv(RESOURCE_NAME)' "$f"
        yq -i '.spec.selector.matchLabels["app.kubernetes.io/instance"]     = "{{ .Release.Name }}"' "$f"
        yq -i '.spec.template.metadata.labels["app.kubernetes.io/name"]     = strenv(RESOURCE_NAME)' "$f"
        yq -i '.spec.template.metadata.labels["app.kubernetes.io/instance"] = "{{ .Release.Name }}"' "$f"
        yq -i '.spec.template.spec.serviceAccountName                      |= sub(strenv(NAME_PREFIX), strenv(RESOURCE_FULLNAME))' "$f"
        yq -i '.spec.template.spec.containers[0].image                      = strenv(IMAGE)' "$f"
        yq -i '.spec.template.spec.containers[0].imagePullPolicy            = "{{ .Values.image.pullPolicy }}"' "$f"
        yq -i '.spec.template.spec.containers[0].imagePullSecrets           = "with12:{{ .Values.image.imagePullSecrets }}"' "$f"
        yq -i '.spec.template.spec.containers[0].resources                  = "{{- .Values.resources | toYaml | nindent 12 }}"' "$f"
        yq -i '.spec.replicas                                               = "{{ .Values.replicaCount }}"' "$f"
        yq -i '.spec.template.spec.nodeSelector                             = "with8:{{ .Values.nodeSelector }}"' "$f"
        yq -i '.spec.template.spec.tolerations                              = "with8:{{ .Values.toleratios }}"' "$f"
        yq -i '.spec.template.spec.affinity                                 = "with8:{{ .Values.affinity }}"' "$f"
        yq -i '.spec.template.metadata.annotations                          = "with8:{{ .Values.podAnnotations }}"' "$f"
        # remove unneeded quoting
        sed -i -r "s/'\\{\\{(.+)}}'/{{\\1}}/g" "$f"
        # introduce with blocks
        sed -i -r -r "s/(\\s+)([^:]+):\s+with([0-9]+):\\{\\{\\s*(.+?)}}/\\1{{- with \\4 }}\\n\\1\\2: {{- toYaml . | nindent \\3 }}\\n\\1{{- end }}/g" "$f"
    fi
    if [ "$kind" = "mutatingwebhookconfiguration" ] || [ "$kind" = "validatingwebhookconfiguration" ]
    then
        yq -i '.webhooks |= map(.clientConfig.service.namespace = "{{ .Release.Namespace }}")' "$f"
        yq -i '.webhooks |= map(.clientConfig.service.name = strenv(RESOURCE_FULLNAME) + "-webhook-service")' "$f"
        yq -i '.metadata.annotations["cert-manager.io/inject-ca-from"] = "{{ .Release.Namespace }}/" + strenv(RESOURCE_FULLNAME) + "-serving-cert"' "$f"
    fi
done

