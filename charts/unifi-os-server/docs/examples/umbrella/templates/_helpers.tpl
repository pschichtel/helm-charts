{{/*
Password of a generated Secret: the existing one if the Secret is already in
the cluster (so upgrades keep it), a new random alphanumeric one otherwise.
Alphanumeric only: the UniFi services put passwords unquoted into connection
strings. Call with (dict "ctx" $ "name" "<secret name>").
*/}}
{{- define "stack.password" -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace .name -}}
{{- if and $existing $existing.data (hasKey $existing.data "password") -}}
{{- index $existing.data "password" | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
