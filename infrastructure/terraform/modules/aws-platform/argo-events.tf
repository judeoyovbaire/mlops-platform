# Argo Events for event-driven ML pipeline triggers
# Deploys the Argo Events controller and creates the argo-events namespace

resource "helm_release" "argo_events" {
  name             = "argo-events"
  namespace        = "argo-events"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-events"
  version          = var.helm_argo_events_version

  values = [
    yamlencode({
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

  depends_on = [helm_release.argo_workflows]
}
