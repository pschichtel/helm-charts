{{/*
Expand the name of the chart.
*/}}
{{- define "powerdns.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "powerdns.fullname" -}}
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
{{- define "powerdns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "powerdns.labels" -}}
helm.sh/chart: {{ include "powerdns.chart" . }}
{{ include "powerdns.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "powerdns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "powerdns.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "powerdns.secretRef" -}}
{{- if and .Ref.name .Ref.key -}}
- name: {{ .Name | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ .Ref.name | quote }}
      key: {{ .Ref.key | quote -}}
{{- else if .Ref.value -}}
- name: {{ .Name | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ include "powerdns.fullname" .Root | quote }}
      key: {{ .Name | quote -}}
{{- else if .Required -}}
{{- fail (print "A value or secretRef must be provided for " .Name "!") -}}
{{- end -}}
{{- end -}}

{{- define "powerdns.secret" -}}
{{- if .Ref.value -}}
{{ .Name | quote }}: {{ .Ref.value | toString | b64enc }}
{{- end -}}
{{- end -}}
