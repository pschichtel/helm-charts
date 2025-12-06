#!/usr/bin/env bash

set -euo pipefail

version="$(yq .appVersion Chart.yaml)"

mkdir -p templates/generated
cd templates/generated
find -mindepth 1 -delete

file='kubernetes.yml'

echo "Updating to $version"
curl -sLf -o "$file" "https://github.com/rabbitmq/messaging-topology-operator/releases/download/v${version}/messaging-topology-operator-with-certmanager.yaml"
yq -s '(.kind | downcase) + "_" + .metadata.name + ".yml"' "$file"
rm -v "$file"
rm -v namespace_*.yml

export RESOURCE_NAME='{{ include "rabbitmq-topology-operator.name" $ }}'
export RESOURCE_FULLNAME='{{ include "rabbitmq-topology-operator.fullname" $ }}'
export NAME_PREFIX='^messaging-topology(-(operator|manager))?'
export IMAGE='{{ print .Values.image.registry "/" .Values.image.repository ":" (.Values.image.tag | default .Chart.AppVersion) }}'

for f in *.yml
do
    kind="$(yq '.kind | downcase' "$f")"
    echo "Processing kind: $kind"
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
        yq -i '.spec.template.spec.volumes[0].secret.secretName             = strenv(RESOURCE_FULLNAME) + "-webhook-cert"' "$f"
        # remove unneeded quoting
        sed -i -r "s/'\\{\\{(.+)}}'/{{\\1}}/g" "$f"
        # introduce with blocks
        sed -i -r -r "s/(\\s+)([^:]+):\s+with([0-9]+):\\{\\{\\s*(.+?)}}/\\1{{- with \\4 }}\\n\\1\\2: {{- toYaml . | nindent \\3 }}\\n\\1{{- end }}/g" "$f"
    fi
    if [ "$kind" = 'issuer' ]
    then
        yq -i '.metadata.name = strenv(RESOURCE_FULLNAME) + "-issuer"' "$f"
    fi
    if [ "$kind" = 'certificate' ]
    then
        yq -i '.spec.secretName = strenv(RESOURCE_FULLNAME) + "-webhook-cert" | .metadata.name = .spec.secretName' "$f"
        yq -i '.spec.issuerRef.name = strenv(RESOURCE_FULLNAME) + "-issuer"' "$f"
        yq -i '.spec.dnsNames |= map(sub("^webhook-service\.rabbitmq-system\.svc", strenv(RESOURCE_FULLNAME) + "-webhook.{{ .Release.Namespace }}.svc"))' "$f"
    fi
    if [ "$kind" = 'service' ]
    then
        yq -i '.metadata.name = strenv(RESOURCE_FULLNAME) + "-webhook"' "$f"
        yq -i '.spec.selector["app.kubernetes.io/name"]     = strenv(RESOURCE_NAME)' "$f"
        yq -i '.spec.selector["app.kubernetes.io/instance"] = "{{ .Release.Name }}"' "$f"
    fi
    if [ "$kind" = 'validatingwebhookconfiguration' ]
    then
        yq -i '.metadata.annotations["cert-manager.io/inject-ca-from"] = "{{ print .Release.Namespace }}/" + strenv(RESOURCE_FULLNAME) + "-webhook-cert"' "$f"
        yq -i '.webhooks |= map(.clientConfig.service.name = strenv(RESOURCE_FULLNAME) + "-webhook" | .clientConfig.service.namespace = "{{ .Release.Namespace }}")' "$f"
    fi
done

