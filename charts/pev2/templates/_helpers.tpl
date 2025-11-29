{{/*
Expand the name of the chart.
*/}}
{{- define "pev2.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pev2.fullname" -}}
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
{{- define "pev2.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pev2.labels" -}}
helm.sh/chart: {{ include "pev2.chart" . }}
{{ include "pev2.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pev2.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pev2.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pev2.commonEnv" -}}
- name: DB_SERVICE
  {{- if .Values.pev2.database.host.value }}
  value: {{ .Values.pev2.database.host.value | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.pev2.database.host.secretName | default (include "pev2.fullname" .) | quote }}
      key: {{ .Values.pev2.database.host.secretKey | quote }}
  {{- end }}
- name: DB_PORT
  {{- if .Values.pev2.database.port.value }}
  value: {{ .Values.pev2.database.port.value | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.pev2.database.port.secretName | default (include "pev2.fullname" .) | quote }}
      key: {{ .Values.pev2.database.port.secretKey | quote }}
  {{- end }}
- name: DB_NAME
  {{- if .Values.pev2.database.name.value }}
  value: {{ .Values.pev2.database.name.value | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.pev2.database.name.secretName | default (include "pev2.fullname" .) | quote }}
      key: {{ .Values.pev2.database.name.secretKey | quote }}
  {{- end }}
- name: DB_USER
  {{- if .Values.pev2.database.username.value }}
  value: {{ .Values.pev2.database.username.value | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.pev2.database.username.secretName | default (include "pev2.fullname" .) | quote }}
      key: {{ .Values.pev2.database.username.secretKey | quote }}
  {{- end }}
- name: DB_PASS
  {{- if .Values.pev2.database.password.value }}
  value: {{ .Values.pev2.database.password.value | quote }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.pev2.database.password.secretName | default (include "pev2.fullname" .) | quote }}
      key: {{ .Values.pev2.database.password.secretKey | quote }}
  {{- end }}
{{- end }}