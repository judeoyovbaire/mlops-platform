# GitOps baseline (ADR-017 decision 6)
#
# ArgoCD owns everything under infrastructure/kubernetes/ (Kyverno governance,
# network policies, quotas, PDBs, SLO rules, dashboards, rollout templates,
# Argo Events). Terraform only installs ArgoCD and this one Application, so
# bootstrap is no longer a manual `kubectl apply` that a fresh cluster could
# skip. Until 2026-11-01 Terraform also applied network-policies.yaml and two
# dashboards itself while ArgoCD reconciled the same objects with prune and
# self-heal - two owners for one resource.

resource "kubectl_manifest" "platform_baseline" {
  yaml_body = file("${path.module}/../../../argocd/platform-baseline.yaml")

  # Every namespace and CRD the kustomization targets must exist before the
  # first sync, or ArgoCD retries and the health wait below times out:
  # namespaces (mlops, mlflow, argo, monitoring, kserve as kubernetes_namespace_v1
  # resources; argocd, argo-events, external-secrets via create_namespace;
  # karpenter via helm_release.karpenter's namespace), the gp3 storage class
  # (EventBus volumes), and CRDs (ClusterPolicy, PrometheusRule/ServiceMonitor/ScrapeConfig,
  # AnalysisTemplate, EventBus/EventSource/Sensor, InferenceService, which
  # the Kyverno governance policies match).
  depends_on = [
    helm_release.argocd,
    helm_release.kyverno,
    helm_release.prometheus_stack,
    helm_release.argo_rollouts,
    helm_release.argo_events,
    helm_release.argo_workflows,
    helm_release.kserve,
    helm_release.external_secrets,
    helm_release.karpenter,
    kubernetes_namespace_v1.mlops,
    kubernetes_namespace_v1.mlflow,
    kubernetes_namespace_v1.argo,
    kubernetes_namespace_v1.monitoring,
    kubernetes_namespace_v1.kserve,
    kubernetes_storage_class_v1.gp3,
  ]
}

# Block the apply until ArgoCD reports the baseline Synced and Healthy, so
# default-deny network policies and the Enforce admission policies exist
# before workloads start. MLflow and MinIO depend on this; the controllers
# that provide the baseline's CRDs (Kyverno, KServe, Argo) necessarily come
# first. Model InferenceServices and pipeline runs are deployed by CI after
# the apply. Sync wait is 11m: the Application's retry policy (5 attempts,
# 20s doubling, 5m cap) gives up after ~10m on the same revision.
# Uses a throwaway kubeconfig so the caller's ~/.kube/config is untouched.
resource "terraform_data" "platform_baseline_ready" {
  triggers_replace = [kubectl_manifest.platform_baseline.uid]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="$(mktemp)"
      trap 'rm -f "$KUBECONFIG"' EXIT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks.cluster_name} --kubeconfig "$KUBECONFIG" >/dev/null
      app=applications.argoproj.io/platform-baseline
      if ! kubectl -n argocd wait "$app" \
            --for=jsonpath='{.status.sync.status}'=Synced --timeout=11m \
         || ! kubectl -n argocd wait "$app" \
            --for=jsonpath='{.status.health.status}'=Healthy --timeout=10m; then
        echo "platform-baseline did not become Synced and Healthy:" >&2
        kubectl -n argocd get "$app" -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}operation={.status.operationState.phase}: {.status.operationState.message}{"\n"}{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}' >&2 || true
        kubectl -n argocd get "$app" -o jsonpath='{range .status.resources[*]}{.kind}/{.namespace}/{.name}: {.status} {.health.status}{"\n"}{end}' >&2 || true
        exit 1
      fi
    EOT
  }
}
