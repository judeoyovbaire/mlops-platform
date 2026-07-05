# OpenCost for Kubernetes cost monitoring
# Provides real-time cost allocation by namespace, pod, and workload

resource "helm_release" "opencost" {
  name             = "opencost"
  namespace        = "opencost"
  create_namespace = true
  repository       = "https://opencost.github.io/opencost-helm-chart"
  chart            = "opencost"
  version          = var.helm_opencost_version

  values = [
    file("${path.module}/../../../helm/common/opencost-values.yaml")
  ]

  depends_on = [helm_release.prometheus_stack]
}
