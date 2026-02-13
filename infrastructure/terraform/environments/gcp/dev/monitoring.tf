# Monitoring Stack
# Deploys Prometheus, Grafana, and AlertManager

resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.helm_prometheus_stack_version
  namespace  = "monitoring"

  values = [
    templatefile("${path.module}/../../../../helm/gcp/prometheus-stack-values.yaml", {
      prometheus_service_account_email = module.gke.prometheus_service_account_email
    })
  ]

  # Skip CRD installation on upgrade
  set {
    name  = "prometheus-node-exporter.hostRootFsMount.enabled"
    value = "false"
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.nginx_ingress,
    kubectl_manifest.grafana_admin_credentials
  ]
}

# Loki - Log Aggregation
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.helm_loki_version
  namespace  = "monitoring"

  values = [file("${path.module}/../../../../helm/common/loki-values.yaml")]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack
  ]
}

# Tempo - Trace Storage Backend
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.helm_tempo_version
  namespace  = "monitoring"

  values = [file("${path.module}/../../../../helm/common/tempo-values.yaml")]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack
  ]
}

# OpenTelemetry Collector - Unified Telemetry Pipeline
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.helm_otel_collector_version
  namespace  = "monitoring"

  values = [file("${path.module}/../../../../helm/common/otel-collector-values.yaml")]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.tempo
  ]
}

# ServiceMonitors for Platform Components

# MLflow ServiceMonitor
resource "kubectl_manifest" "mlflow_service_monitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: mlflow
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: mlflow
      namespaceSelector:
        matchNames:
          - mlflow
      endpoints:
        - port: http
          interval: 30s
          path: /metrics
  YAML

  depends_on = [helm_release.prometheus_stack, helm_release.mlflow]
}

# Argo Workflows PodMonitor
resource "kubectl_manifest" "argo_workflows_pod_monitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PodMonitor
    metadata:
      name: argo-workflows
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: argo-workflows-server
      namespaceSelector:
        matchNames:
          - argo
      podMetricsEndpoints:
        - port: metrics
          interval: 30s
  YAML

  depends_on = [helm_release.prometheus_stack, helm_release.argo_workflows]
}

# PrometheusRules for Alerting

resource "kubectl_manifest" "mlops_prometheus_rules" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: mlops-platform-rules
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      groups:
        - name: mlops-platform
          rules:
            - alert: HighInferenceLatency
              expr: histogram_quantile(0.99, sum(rate(inference_request_duration_seconds_bucket[5m])) by (le, model)) > 1
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: High inference latency detected
                description: "Model {{ $labels.model }} has p99 latency > 1s"

            - alert: HighInferenceErrorRate
              expr: sum(rate(inference_request_errors_total[5m])) by (model) / sum(rate(inference_request_total[5m])) by (model) > 0.05
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: High inference error rate
                description: "Model {{ $labels.model }} has error rate > 5%"

            - alert: MLflowDown
              expr: up{job="mlflow"} == 0
              for: 2m
              labels:
                severity: critical
              annotations:
                summary: MLflow is down
                description: "MLflow has been unreachable for more than 2 minutes"

            - alert: ArgoWorkflowsFailed
              expr: sum(argo_workflows_count{status="Failed"}) > 0
              for: 1m
              labels:
                severity: warning
              annotations:
                summary: Argo workflow failed
                description: "There are failed Argo workflows"

            - alert: GPUNodeHighUtilization
              expr: avg(container_accelerator_duty_cycle{accelerator_type="nvidia"}) > 90
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: GPU utilization is high
                description: "GPU utilization has been above 90% for 10 minutes"
  YAML

  depends_on = [helm_release.prometheus_stack]
}
