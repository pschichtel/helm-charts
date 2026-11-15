{{/*
Expand the name of the chart.
*/}}
{{- define "dawarich.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dawarich.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dawarich.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "dawarich.labels" -}}
helm.sh/chart: {{ include "dawarich.chart" . }}
{{ include "dawarich.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "dawarich.labelsSidekiq" -}}
helm.sh/chart: {{ include "dawarich.chart" . }}
{{ include "dawarich.selectorLabelsSidekiq" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dawarich.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dawarich.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "dawarich.selectorLabelsSidekiq" -}}
app.kubernetes.io/name: {{ include "dawarich.fullname" . | printf "%s-sidekiq" }}
app.kubernetes.io/instance: {{ .Release.Name | printf "%s-sidekiq" }}
{{- end }}

{{- define "dawarich.environmentSetup" -}}
{{- range $key, $value := .environment }}
{{- if $value }}
{{ $key | snakecase | upper | indent 2 }}: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end }}

{{- define "dawarich.volumes" -}}
- name: tmp
  emptyDir:
    medium: Memory
    sizeLimit: 256Mi
{{- if .Values.persistence.public.enabled }}
- name: public
  persistentVolumeClaim:
    claimName: {{ default (printf "%s-public" (include "dawarich.fullname" .)) .Values.persistence.public.existingClaim }}
{{- end }}
{{- if .Values.persistence.watched.enabled }}
- name: watched
  persistentVolumeClaim:
    claimName: {{ default (printf "%s-watched" (include "dawarich.fullname" .)) .Values.persistence.watched.existingClaim }}
{{- else }}
- name: watched
  emptyDir:
    sizeLimit: 256Mi
{{- end }}
{{- if .Values.persistence.storage.enabled }}
- name: storage
  persistentVolumeClaim:
    claimName: {{ default (printf "%s-storage" (include "dawarich.fullname" .)) .Values.persistence.storage.existingClaim }}
{{- end }}
{{- if .Values.dawarich.extraVolumes }}
{{ toYaml .Values.dawarich.extraVolumes | indent 2 }}
{{- end }}
{{- end }}

{{- define "dawarich.commonVolumeMounts" -}}
- name: tmp
  mountPath: /var/app/tmp
  subPath: app-tmp
- name: tmp
  mountPath: /tmp
  subPath: tmp
{{- if .Values.persistence.public.enabled }}
- name: public
  mountPath: /var/app/public
{{- end }}
{{- if .Values.persistence.storage.enabled }}
- name: storage
  mountPath: /var/app/storage
{{- end }}
- name: watched
  mountPath: /var/app/tmp/imports/watched
{{- end }}

{{- define "dawarich.volumeMounts" -}}
{{- include "dawarich.commonVolumeMounts" . }}
{{- if .Values.dawarich.extraVolumeMounts }}
{{ toYaml .Values.dawarich.extraVolumeMounts | indent 2 }}
{{- end }}
{{- end }}

{{- define "dawarich.sidekiqVolumeMounts" -}}
{{- include "dawarich.commonVolumeMounts" . }}
{{- end }}

{{- define "dawarich.envFrom" -}}
- configMapRef:
    name: {{ include "dawarich.fullname" . }}-config
{{- if .Values.existingEnvSecret }}
- secretRef:
    name: {{ .Values.existingEnvSecret }}
{{- end }}
{{- end }}

{{- define "dawarich.prometheusPort" }}9394{{ end }}

{{- define "dawarich.livenessProbe" }}
httpGet:
  path: /api/v1/health
  port: http
  httpHeaders:
    - name: Host
      value: {{ .Values.dawarich.hosts | first }}
{{- end }}

{{- define "dawarich.readinessProbe" }}
{{- include "dawarich.livenessProbe" . }}
{{- end }}

{{- define "dawarich.startupProbe" }}
{{- include "dawarich.livenessProbe" . }}
initialDelaySeconds: 30
periodSeconds: 10
failureThreshold: 10
{{- end }}

{{- define "dawarich.secretValue" -}}
{{- $value := get .Root.Values.secret.stringData .Key }}
{{- if $value }}
{{- $value = $value | toString }}
{{ .Key | quote }}: {{ ternary (tpl $value .Root) $value (not (not .Template)) | b64enc }}
{{- end }}
{{- end }}

{{- define "dawarich.secretValueEnvRef" }}
{{- if or .Value (not .Optional) }}
- name: {{ .EnvName | quote }}
  valueFrom:
    secretKeyRef:
        {{- include "dawarich.secretKeyRef" . | nindent 6 }}
{{- end }}
{{- end }}

{{- define "dawarich.secretKeyRef" }}
{{- if or .Value (not .Optional) -}}
{{- if ne .Value nil -}}
name: {{ .Value.name | default (include "dawarich.secretName" .Root) }}
key: {{ .Value.key | quote }}
{{- else }}
name: {{ include "dawarich.secretName" .Root }}
key: {{ .Key | quote }}
{{- end }}
optional: {{ not (not .Optional) }}
{{- end }}
{{- end }}

{{- define "dawarich.secretName" -}}
{{ .Release.Name }}
{{- end }}

{{- define "dawarich.securityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
{{- end }}

{{- define "dawarich.podSecurityContext" -}}
securityContext:
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
  runAsNonRoot: true
  runAsGroup: 1000
  runAsUser: 1000
  seccompProfile:
    type: RuntimeDefault
{{- end }}