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
}

# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.helm_prometheus_stack_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = concat(
    [
      templatefile("${path.module}/../../../helm/aws/prometheus-stack-values.yaml", {
        slack_notifications_enabled = var.slack_notifications_enabled
        slack_channel               = var.slack_channel
      })
    ],
    # Durable telemetry for burst clusters (ADR-016). Off by default so the
    # platform never depends on an unprovisioned Grafana Cloud secret.
    var.enable_grafana_cloud_remote_write ? [
      templatefile("${path.module}/../../../helm/aws/grafana-cloud-remote-write-values.yaml", {
        remote_write_url = var.grafana_cloud_remote_write_url
      })
    ] : []
  )

  # Increase timeout for large chart with many CRDs
  timeout = 1200
  wait    = true

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    time_sleep.alb_controller_ready
  ]
}

# Loki - Log Aggregation with S3 Storage
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.helm_loki_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Use AWS-specific values with S3 storage
  values = [
    templatefile("${path.module}/../../../helm/aws/loki-values.yaml", {
      loki_s3_bucket     = var.eks.loki_s3_bucket
      loki_irsa_role_arn = var.eks.loki_irsa_role_arn
      aws_region         = var.aws_region
    })
  ]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack,
  ]
}

# Tempo - Trace Storage Backend with S3 Storage
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.helm_tempo_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Use AWS-specific values with S3 storage
  values = [
    templatefile("${path.module}/../../../helm/aws/tempo-values.yaml", {
      tempo_s3_bucket     = var.eks.tempo_s3_bucket
      tempo_irsa_role_arn = var.eks.tempo_irsa_role_arn
      aws_region          = var.aws_region
    })
  ]

  timeout = 600

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus_stack,
  ]
}

# OpenTelemetry Collector - Unified Telemetry Pipeline
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.helm_otel_collector_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../helm/common/otel-collector-values.yaml")]

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

  values = [file("${path.module}/../../../helm/common/alloy-values.yaml")]

  timeout = 300

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.loki
  ]
}

# Store Grafana password in SSM
resource "aws_ssm_parameter" "grafana_admin_password" {
  name        = "/${var.cluster_name}/grafana/admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = var.grafana_admin_password
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

# network-policies.yaml and the mlops-overview / cloud-cost dashboards used
# to be applied here as well as by ArgoCD. ArgoCD is now the only owner
# (gitops-baseline.tf). The removed blocks drop them from any existing state
# without deleting the live objects that ArgoCD manages.
removed {
  from = kubectl_manifest.network_policies
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.grafana_mlops_overview_dashboard
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.grafana_cloud_cost_dashboard
  lifecycle {
    destroy = false
  }
}

# Grafana Cloud remote_write credentials (ADR-016) - synced from Secrets
# Manager only when the feature is enabled. Prometheus references the
# resulting secret via basicAuth in the remote_write overlay.
resource "kubectl_manifest" "grafana_cloud_remote_write_secret" {
  count = var.enable_grafana_cloud_remote_write ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "grafana-cloud-remote-write"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-sm"
        kind = "ClusterSecretStore"
      }
      target = { name = "grafana-cloud-remote-write" }
      data = [
        {
          secretKey = "username"
          remoteRef = { key = "${var.cluster_name}/grafana-cloud/remote-write", property = "username" }
        },
        {
          secretKey = "password"
          remoteRef = { key = "${var.cluster_name}/grafana-cloud/remote-write", property = "password" }
        },
      ]
    }
  })

  depends_on = [helm_release.external_secrets]
}
