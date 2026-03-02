{{/*
Expand the name of the chart.
*/}}
{{- define "jdownloader.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "jdownloader.fullname" -}}
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
{{- define "jdownloader.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "jdownloader.labels" -}}
helm.sh/chart: {{ include "jdownloader.chart" . }}
{{ include "jdownloader.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "jdownloader.selectorLabels" -}}
app.kubernetes.io/name: {{ include "jdownloader.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "jdownloader.image" -}}
{{- $repo := print .Values.image.registry "/" .Values.image.repository }}
{{- if .Values.image.digest }}
image: {{ print $repo "@" .Values.image.digest | quote }}
{{- else }}
image: {{ print $repo ":" (.Values.image.tag | default (print "v" .Chart.AppVersion)) | quote }}
{{- end }}
imagePullPolicy: {{ .Values.image.pullPolicy }}
{{- end }}

{{- define "jdownloader.securityContext" -}}
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
{{- end }}

