# Argo Rollouts for Progressive Delivery
# Installed only as the AnalysisRun engine (ADR-016); no Rollout objects

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = var.helm_argo_rollouts_version

  values = [
    yamlencode({
      dashboard = {
        enabled = true
        service = {
          type = "ClusterIP"
        }
      }
      controller = {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled   = true
            namespace = "monitoring"
          }
        }
      }
    })
  ]

  depends_on = [helm_release.prometheus_stack]
}
