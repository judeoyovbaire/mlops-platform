# Monitoring Stack - Prometheus + Grafana

resource "helm_release" "prometheus_stack" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.helm_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/azure/prometheus-stack-values.yaml")
  ]

  # Use existing Grafana admin secret from Key Vault
  set {
    name  = "grafana.admin.existingSecret"
    value = "grafana-admin-credentials"
  }

  set {
    name  = "grafana.admin.userKey"
    value = "admin-user"
  }

  set {
    name  = "grafana.admin.passwordKey"
    value = "admin-password"
  }

  depends_on = [
    module.aks,
    helm_release.nginx_ingress,
    kubectl_manifest.grafana_external_secret
  ]
}

# Loki - Log Aggregation
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = var.helm_loki_version
  namespace        = "monitoring"
  create_namespace = false

  values = [file("${path.module}/../../../../helm/common/loki-values.yaml")]

  timeout = 600

  depends_on = [helm_release.prometheus_stack]
}

# Tempo - Trace Storage Backend
resource "helm_release" "tempo" {
  name             = "tempo"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  version          = var.helm_tempo_version
  namespace        = "monitoring"
  create_namespace = false

  values = [file("${path.module}/../../../../helm/common/tempo-values.yaml")]

  timeout = 600

  depends_on = [helm_release.prometheus_stack]
}

# OpenTelemetry Collector - Unified Telemetry Pipeline
resource "helm_release" "otel_collector" {
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.helm_otel_collector_version
  namespace        = "monitoring"
  create_namespace = false

  values = [file("${path.module}/../../../../helm/common/otel-collector-values.yaml")]

  timeout = 600

  depends_on = [helm_release.tempo]
}

# Grafana Alloy - Log Shipping Agent (ships logs to Loki)
resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = var.helm_alloy_version
  namespace        = "monitoring"
  create_namespace = false

  values = [file("${path.module}/../../../../helm/common/alloy-values.yaml")]

  timeout = 300

  depends_on = [helm_release.loki]
}

# Grafana Dashboards - ConfigMaps for sidecar auto-discovery
resource "kubectl_manifest" "grafana_mlops_overview_dashboard" {
  yaml_body = file("${path.module}/../../../../kubernetes/dashboards/mlops-overview-dashboard.yaml")

  depends_on = [helm_release.prometheus_stack]
}

resource "kubectl_manifest" "grafana_cloud_cost_dashboard" {
  yaml_body = file("${path.module}/../../../../kubernetes/dashboards/cloud-cost-dashboard.yaml")

  depends_on = [helm_release.prometheus_stack]
}

# ServiceMonitors for MLOps Components

# MLflow ServiceMonitor
resource "kubectl_manifest" "mlflow_servicemonitor" {
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
          path: /metrics
          interval: 30s
  YAML

  depends_on = [helm_release.prometheus_stack]
}

# KServe ServiceMonitor
resource "kubectl_manifest" "kserve_servicemonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: kserve-controller
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      selector:
        matchLabels:
          control-plane: kserve-controller-manager
      namespaceSelector:
        matchNames:
          - kserve
      endpoints:
        - port: https
          path: /metrics
          interval: 30s
          scheme: https
          tlsConfig:
            insecureSkipVerify: true
  YAML

  depends_on = [helm_release.prometheus_stack]
}

# Argo Workflows ServiceMonitor
resource "kubectl_manifest" "argo_workflows_servicemonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
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
      endpoints:
        - port: web
          path: /metrics
          interval: 30s
  YAML

  depends_on = [helm_release.prometheus_stack]
}

# KEDA ServiceMonitor
resource "kubectl_manifest" "keda_servicemonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: keda
      namespace: monitoring
      labels:
        release: prometheus
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: keda-operator
      namespaceSelector:
        matchNames:
          - keda
      endpoints:
        - port: metricsservice
          path: /metrics
          interval: 30s
  YAML

  depends_on = [helm_release.prometheus_stack]
}

# Network Policies - Managed via Terraform for lifecycle tracking
data "kubectl_file_documents" "network_policies" {
  content = file("${path.module}/../../../../kubernetes/network-policies.yaml")
}

resource "kubectl_manifest" "network_policies" {
  for_each  = data.kubectl_file_documents.network_policies.manifests
  yaml_body = each.value

  depends_on = [module.aks]
}
