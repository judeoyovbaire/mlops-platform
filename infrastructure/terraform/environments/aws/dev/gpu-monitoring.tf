# NVIDIA DCGM Exporter for GPU monitoring
# DaemonSet that exposes GPU metrics to Prometheus on GPU-enabled nodes

resource "helm_release" "dcgm_exporter" {
  name             = "dcgm-exporter"
  namespace        = "monitoring"
  create_namespace = false
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = var.helm_dcgm_exporter_version

  values = [
    file("${path.module}/../../../../helm/common/dcgm-exporter-values.yaml")
  ]

  depends_on = [helm_release.prometheus_stack]
}
