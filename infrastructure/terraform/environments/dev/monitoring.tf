# =============================================================================
# Observability Stack - Prometheus & Grafana
# =============================================================================

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/name"    = "monitoring"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Monitoring stack needs baseline for node-exporter hostPath mounts
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "baseline"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "baseline"
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
  version    = "72.6.2"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../helm/aws/prometheus-stack-values.yaml")]

  # Increase timeout for CRD installation
  timeout = 900

  set {
    name  = "grafana.adminPassword"
    value = random_password.argocd_admin.result # Reuse generated password
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.aws_load_balancer_controller
  ]
}

# Store Grafana password in SSM
resource "aws_ssm_parameter" "grafana_admin_password" {
  name        = "/${var.cluster_name}/grafana/admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = random_password.argocd_admin.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}
