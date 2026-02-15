# Observability Stack - Prometheus & Grafana

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/name"    = "monitoring"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Monitoring stack needs privileged for node-exporter (hostNetwork, hostPID, hostPath, hostPort)
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }

  depends_on = [module.eks]
}

# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.helm_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../../helm/aws/prometheus-stack-values.yaml")]

  # Increase timeout for large chart with many CRDs
  timeout = 1200
  wait    = true

  set {
    name  = "grafana.adminPassword"
    value = random_password.grafana_admin.result
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    time_sleep.alb_controller_ready
  ]
}

# Loki - Log Aggregation
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.helm_loki_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

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
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

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
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../../helm/common/otel-collector-values.yaml")]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.tempo
  ]
}

# Grafana Alloy - Log Shipping Agent (ships logs to Loki)
resource "helm_release" "alloy" {
  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.helm_alloy_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../../helm/common/alloy-values.yaml")]

  timeout = 300

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.loki
  ]
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

# Store Grafana password in SSM
resource "aws_ssm_parameter" "grafana_admin_password" {
  name        = "/${var.cluster_name}/grafana/admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = random_password.grafana_admin.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

# Network Policies - Managed via Terraform for lifecycle tracking
data "kubectl_file_documents" "network_policies" {
  content = file("${path.module}/../../../../kubernetes/network-policies.yaml")
}

resource "kubectl_manifest" "network_policies" {
  for_each  = data.kubectl_file_documents.network_policies.manifests
  yaml_body = each.value

  depends_on = [module.eks]
}
