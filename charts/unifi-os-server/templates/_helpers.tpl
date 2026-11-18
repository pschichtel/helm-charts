{{/*
Expand the name of the chart.
*/}}
{{- define "unifi-os-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "unifi-os-server.fullname" -}}
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
{{- define "unifi-os-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "unifi-os-server.labels" -}}
helm.sh/chart: {{ include "unifi-os-server.chart" . }}
{{ include "unifi-os-server.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "unifi-os-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "unifi-os-server.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "unifi-os-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "unifi-os-server.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image (all services use the same image).
*/}}
{{- define "unifi-os-server.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Stable console UUID: console.uuid, or derived from namespace + fullname
(sha256, formatted as a version-5-style UUID) so that it does not change
between upgrades or `helm template` runs.
*/}}
{{- define "unifi-os-server.uuid" -}}
{{- if .Values.console.uuid }}
{{- .Values.console.uuid }}
{{- else }}
{{- $h := printf "%s/%s" .Release.Namespace (include "unifi-os-server.fullname" .) | sha256sum }}
{{- printf "%s-%s-5%s-8%s-%s" (substr 0 8 $h) (substr 8 12 $h) (substr 13 16 $h) (substr 17 20 $h) (substr 20 32 $h) }}
{{- end }}
{{- end }}

{{/*
Console firmware version string (/usr/lib/version).
*/}}
{{- define "unifi-os-server.firmwareVersion" -}}
{{- .Values.console.identity.version | default (printf "UOSSERVER.0000000.%s.000000.0000.0000" (.Values.image.tag | default .Chart.AppVersion)) }}
{{- end }}

{{/*
Name of the data PVC.
*/}}
{{- define "unifi-os-server.pvcName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "unifi-os-server.fullname" .)) }}
{{- end }}

{{/*
Fail early on missing external service settings.
*/}}
{{- define "unifi-os-server.validate" -}}
{{- $missing := list }}
{{- $checks := list }}
{{- range $svc := list "unifiCore" "ulpGo" "uidAgent" "ucsAgent" "unifiDirectory" }}
{{- $fields := list "host" "port" "username" "password" "database" }}
{{- if eq $svc "ulpGo" }}{{ $fields = append $fields "syslogDatabase" }}{{ end }}
{{- $checks = append $checks (dict "path" (printf "postgresql.auth.%s" $svc) "conn" (index $.Values.postgresql.auth $svc | default dict) "fields" $fields) }}
{{- end }}
{{- $checks = append $checks (dict "path" "mongodb" "conn" .Values.mongodb "fields" (list "hosts" "replicaSet" "authSource" "username" "password" "database" "statDatabase")) }}
{{- $checks = append $checks (dict "path" "rabbitmq" "conn" .Values.rabbitmq "fields" (list "host" "port" "username" "password")) }}
{{- range $c := $checks }}
{{- range $f := $c.fields }}
{{- if not (include "unifi-os-server.fieldSet" (dict "path" $c.path "conn" $c.conn "field" $f)) }}{{ $missing = append $missing (printf "%s.%s" $c.path $f) }}{{ end }}
{{- if and (eq $f "password") (index $c.conn $f | default dict).value }}{{ $missing = append $missing (printf "%s.password from a Secret (value is not allowed)" $c.path) }}{{ end }}
{{- end }}
{{- end }}
{{- if and .Values.rabbitmq.tls.enabled (not .Values.rabbitmq.tls.caSecret) }}{{ $missing = append $missing "rabbitmq.tls.caSecret" }}{{ end }}
{{- if $missing }}
{{- fail (printf "\n\nunifi-os-server needs external PostgreSQL, MongoDB and RabbitMQ. Missing values: %s\nSee the chart README." (join ", " $missing)) }}
{{- end }}
{{- end }}

{{/*
Connection settings of the external services: every field of
postgresql.auth.<service>, mongodb and rabbitmq that names a connection
setting is either
  {value: <value>}              a plain value (not for password; a list is
                                joined with ","), or
  {key: <key>, name: <Secret>}  read from a Secret; name defaults to the
                                section's secretName, so every field can come
                                from a different Secret.
value wins over key (values.yaml defaults are merged with user values, so a
user-set value must override a default key). Fields without either fall back
to the defaults below; fields listed with "" are optional.
*/}}
{{- define "unifi-os-server.fieldDefaults" -}}
postgresql.auth.unifiCore.database: unifi-core
postgresql.auth.ulpGo.database: ulp-go
postgresql.auth.ulpGo.syslogDatabase: ulp-go-syslog
postgresql.auth.uidAgent.database: uid
postgresql.auth.ucsAgent.database: ucs-agent
postgresql.auth.unifiDirectory.database: unifi-directory
mongodb.replicaSet: ""
mongodb.authSource: admin
mongodb.database: ace
mongodb.statDatabase: ace_stat
{{- end }}

{{/*
Non-empty if a field is usable. Call with (dict "path" "<values path>" "conn" <section values> "field" "<field>").
*/}}
{{- define "unifi-os-server.fieldSet" -}}
{{- $f := index .conn .field | default dict }}
{{- if and (ne .field "password") (ne (toString ($f.value | default "")) "") }}set
{{- else if and $f.key (or $f.name .conn.secretName) }}set
{{- else if hasKey (include "unifi-os-server.fieldDefaults" . | fromYaml) (printf "%s.%s" .path .field) }}set
{{- end }}
{{- end }}

{{/*
One env var from a field (validated by unifi-os-server.validate).
Call with (dict "env" "<VAR>" "path" "<values path>" "conn" <section values> "field" "<field>").
*/}}
{{- define "unifi-os-server.fieldEnv" -}}
{{- $f := index .conn .field | default dict }}
- name: {{ .env }}
{{- if and (ne .field "password") (ne (toString ($f.value | default "")) "") }}
  value: {{ (kindIs "slice" $f.value | ternary (join "," $f.value) (toString $f.value)) | quote }}
{{- else if $f.key }}
  valueFrom:
    secretKeyRef:
      name: {{ $f.name | default .conn.secretName | quote }}
      key: {{ $f.key | quote }}
{{- else }}
  value: {{ get (include "unifi-os-server.fieldDefaults" . | fromYaml) (printf "%s.%s" .path .field) | toString | quote }}
{{- end }}
{{- end }}

{{/*
Postgres connection env for one container.
Call with (dict "svc" "<service>" "conn" <postgresql.auth.x> "role" "<required role or empty>").
*/}}
{{- define "unifi-os-server.postgresEnv" -}}
{{- $p := printf "postgresql.auth.%s" .svc }}
{{- include "unifi-os-server.fieldEnv" (dict "env" "PGHOST" "path" $p "conn" .conn "field" "host") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" "PGPORT" "path" $p "conn" .conn "field" "port") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" "PGUSER" "path" $p "conn" .conn "field" "username") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" "PGPASSWORD" "path" $p "conn" .conn "field" "password") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" "DB_NAME" "path" $p "conn" .conn "field" "database") }}
{{- with .role }}
- name: PG_REQUIRED_USER
  value: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
MongoDB and RabbitMQ connection env for the Network application.
*/}}
{{- define "unifi-os-server.networkAppDataEnv" -}}
{{- $m := .Values.mongodb }}
{{- range $e := list (list "MONGO_HOSTS" "hosts") (list "MONGO_REPLICA_SET" "replicaSet") (list "MONGO_AUTH_SOURCE" "authSource") (list "MONGO_DATABASE" "database") (list "MONGO_STAT_DATABASE" "statDatabase") (list "MONGO_USERNAME" "username") (list "MONGO_PASSWORD" "password") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" (index $e 0) "path" "mongodb" "conn" $m "field" (index $e 1)) }}
{{- end }}
- name: MONGO_TLS
  value: {{ $m.tls | quote }}
- name: MONGO_EXTRA_OPTIONS
  value: {{ $m.extraOptions | quote }}
{{- $r := .Values.rabbitmq }}
{{- range $e := list (list "RABBITMQ_HOST" "host") (list "RABBITMQ_PORT" "port") (list "RABBITMQ_USERNAME" "username") (list "RABBITMQ_PASSWORD" "password") }}
{{ include "unifi-os-server.fieldEnv" (dict "env" (index $e 0) "path" "rabbitmq" "conn" $r "field" (index $e 1)) }}
{{- end }}
{{- if $r.tls.enabled }}
- name: RABBITMQ_TLS
  value: "true"
- name: RABBITMQ_TLS_CA_FILE
  value: /etc/rabbitmq-ca/{{ $r.tls.caKey }}
- name: RABBITMQ_TLS_VERIFY_HOSTNAME
  value: {{ $r.tls.verifyHostname | quote }}
{{- end }}
{{- end }}

{{/*
Mounts shared by every container: entrypoint scripts, the shared /run,
the console identity files and user-supplied volumeMounts.
*/}}
{{- define "unifi-os-server.commonMounts" -}}
- name: scripts
  mountPath: /scripts
  readOnly: true
- name: run
  mountPath: /run
- name: identity
  mountPath: /usr/lib/platform
  subPath: platform
  readOnly: true
- name: identity
  mountPath: /usr/lib/product_name
  subPath: product_name
  readOnly: true
- name: identity
  mountPath: /usr/lib/app_model
  subPath: app_model
  readOnly: true
- name: identity
  mountPath: /usr/lib/version
  subPath: version
  readOnly: true
{{- with .Values.volumeMounts }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Data volume mount. Call with (dict "root" $ "path" "/data/x" "sub" "x").
*/}}
{{- define "unifi-os-server.dataMount" -}}
- name: data
  mountPath: {{ .path }}
  subPath: {{ .sub }}
{{- end }}

{{/*
Static config mount for a Go service: its props file and, if any, logger config.
Call with (dict "app" "<app>" "logger" "<path in image or empty>").
*/}}
{{- define "unifi-os-server.goConfigMounts" -}}
- name: config
  mountPath: /config/{{ .app }}.props
  subPath: {{ .app }}.props
  readOnly: true
{{- if .logger }}
- name: config
  mountPath: {{ .logger }}
  subPath: logger-{{ .app }}.yaml
  readOnly: true
{{- end }}
{{- end }}

{{/*
Container basics shared by every container.
Call with (dict "root" $ "name" "<container>" "script" "<entrypoint>" "values" <containers.x>).
*/}}
{{- define "unifi-os-server.containerBase" -}}
- name: {{ .name }}
  image: {{ include "unifi-os-server.image" .root | quote }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  {{- with .root.Values.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  command: [{{ .script | quote }}]
  {{- with .values.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
One Service of the pod. Call with (dict "root" $ "name" <name> "cfg" <values of service.web or service.device>).
*/}}
{{- define "unifi-os-server.service" -}}
{{- $cfg := .cfg -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    {{- include "unifi-os-server.labels" .root | nindent 4 }}
  {{- with $cfg.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ $cfg.type }}
  {{- if and (eq $cfg.type "LoadBalancer") $cfg.loadBalancerIP }}
  loadBalancerIP: {{ $cfg.loadBalancerIP }}
  {{- end }}
  {{- with $cfg.loadBalancerSourceRanges }}
  loadBalancerSourceRanges:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if and $cfg.externalTrafficPolicy (has $cfg.type (list "LoadBalancer" "NodePort")) }}
  externalTrafficPolicy: {{ $cfg.externalTrafficPolicy }}
  {{- end }}
  ports:
    {{- range $name, $p := $cfg.ports }}
    {{- if $p.enabled }}
    - name: {{ $name }}
      port: {{ $p.port }}
      targetPort: {{ $name }}
      protocol: {{ $p.protocol | default "TCP" }}
      {{- if and $p.nodePort (has $cfg.type (list "LoadBalancer" "NodePort")) }}
      nodePort: {{ $p.nodePort }}
      {{- end }}
    {{- end }}
    {{- end }}
  selector:
    {{- include "unifi-os-server.selectorLabels" .root | nindent 4 }}
{{- end }}
