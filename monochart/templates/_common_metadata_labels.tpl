{{/* vim: set filetype=mustache: */}}
{{- /*
From obsolete Kubernetes Incubator Common chart
https://github.com/helm/charts/blob/master/incubator/common/

common.labelize takes a dict or map and generates labels.

Values will be quoted. Keys will not.

Example output:

  first: "Matt"
  last: "Butcher"

*/ -}}
{{- define "common.labelize" -}}
    {{- range $k, $v := . }}
        {{ $k }}: {{ $v | quote }}
    {{- end -}}
{{- end -}}

{{- /*
common.chartref prints a chart name and version.

It does minimal escaping for use in Kubernetes labels.

Example output:

  zookeeper-1.2.3
  wordpress-3.2.1_20170219

*/ -}}
{{- define "common.chartref" -}}
    {{- replace "+" "_" .Chart.Version | printf "%s-%s" .Chart.Name -}}
{{- end -}}

{{/*
Kubernetes standard labels
*/}}
{{- define "common.labels.standard" -}}
app.kubernetes.io/name: {{ include "common.fullname" . }}
helm.sh/chart: {{ include "common.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}

{{- end -}}

{{/*
Labels to use in:
  deploy.spec.selector.matchLabels,
  statefulset.spec.selector.matchLabels,
  statefulset.spec.volumeClaimTemplates.labels
*/}}
{{- define "common.labels.short" -}}
app.kubernetes.io/name: {{ include "common.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
