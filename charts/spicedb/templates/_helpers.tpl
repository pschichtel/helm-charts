{{/*
Expand the name of the chart.
*/}}
{{- define "spicedb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spicedb.fullname" -}}
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
{{- define "spicedb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spicedb.labels" -}}
helm.sh/chart: {{ include "spicedb.chart" . }}
{{ include "spicedb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spicedb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spicedb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spicedb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spicedb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "spicedb.terminationLogPath" -}}
/dev/termination-log
{{- end }}

{{- define "spicedb.env" -}}
env:
- name: SPICEDB_POD_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.name
- name: SPICEDB_LOG_LEVEL
  value: {{ .Values.spicedb.logLevel | quote }}
- name: SPICEDB_LOG_FORMAT
  value: {{ .Values.spicedb.logFormat | quote }}
- name: SPICEDB_SKIP_RELEASE_CHECK
  value: 'true'
- name: SPICEDB_DISPATCH_CLUSTER_ENABLED
  value: "{{ .Values.spicedb.dispatchClusterEnabled }}"
{{- if .Values.spicedb.dispatchClusterEnabled }}
- name: SPICEDB_DISPATCH_UPSTREAM_ADDR
  value: {{ print "kubernetes:///" (include "spicedb.fullname" .) "." .Release.Namespace ":dispatch" | quote }}
{{- end }}
- name: SPICEDB_HTTP_ENABLED
  value: "{{ .Values.spicedb.httpEnabled }}"
{{- with .Values.spicedb.shutdownGracePeriod }}
- name: SPICEDB_GRPC_SHUTDOWN_GRACE_PERIOD
  value: {{ . | quote }}
{{- end }}
- name: SPICEDB_TERMINATION_LOG_PATH
  value: {{ include "spicedb.terminationLogPath" . | quote }}
{{- if .Values.spicedb.datastore.engine }}
- name: SPICEDB_DATASTORE_ENGINE
  value: {{ .Values.spicedb.datastore.engine | quote }}
- name: SPICEDB_DATASTORE_CONN_URI
  valueFrom:
    secretKeyRef:
      {{- with .Values.spicedb.datastore.connectionUri }}
      {{- if .value }}
      name: {{ include "spicedb.fullname" $ }}
      key: datastore_connection_uri
      {{- else }}
      name: {{ .secretName | required ".spicedb.datastore.connectionUri.value or .secretName is required!" }}
      key: {{ .secretKey | required ".spicedb.datastore.connectionUri.value or .secretKey is required!" | quote }}
      {{- end }}
      {{- end }}
{{- if .Values.spicedb.datastore.readReplica.enabled }}
- name: SPICEDB_DATASTORE_READ_REPLICA_CONN_URI
  valueFrom:
    secretKeyRef:
      {{- with .Values.spicedb.datastore.readReplica.connectionUri }}
      {{- if .value }}
      name: {{ include "spicedb.fullname" $ }}
      key: datastore_read_replica_connection_uri
      {{- else }}
      name: {{ .secretName | required ".spicedb.datastore.readReplica.connectionUri.value or .secretName is required!" }}
      key: {{ .secretKey | required ".spicedb.datastore.readReplica.connectionUri.value or .secretKey is required!" | quote }}
      {{- end }}
      {{- end }}
{{- end }}
{{- end }}
- name: SPICEDB_GRPC_PRESHARED_KEY
  valueFrom:
    secretKeyRef:
      {{- with .Values.spicedb.grpcPresharedKey }}
      {{- if .value }}
      name: {{ include "spicedb.fullname" $ }}
      key: grpc_preshared_key
      {{- else }}
      name: {{ .secretName | required ".spicedb.grpcPresharedKey.value or .secretName is required!" }}
      key: {{ .secretKey | required ".spicedb.grpcPresharedKey.value or .secretName is required!" | quote }}
      {{- end }}
      {{- end }}
{{- with .Values.extraEnv }}
{{- . | toYaml | nindent 0 }}
{{- end }}
{{- end }}

{{- define "spicedb.containerImage" -}}
image: {{ print .Values.image.registry "/" .Values.image.repository ":" (.Values.image.tag | default (print "v" .Chart.AppVersion)) | quote }}
imagePullPolicy: {{ .Values.image.pullPolicy }}
{{- end }}
