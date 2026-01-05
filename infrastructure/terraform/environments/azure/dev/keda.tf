# =============================================================================
# KEDA - Kubernetes Event-Driven Autoscaling
# =============================================================================
# Replaces Karpenter for Azure (Karpenter is AWS-only)
# KEDA works with Cluster Autoscaler to provide pod-driven node scaling
# =============================================================================

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = var.helm_keda_version
  namespace        = "keda"
  create_namespace = true

  values = [
    file("${path.module}/../../../../helm/azure/keda-values.yaml")
  ]

  # Workload Identity configuration
  set {
    name  = "podIdentity.azureWorkload.enabled"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.azure\\.workload\\.identity/client-id"
    value = module.aks.keda_identity_client_id
  }

  depends_on = [module.aks]
}

# =============================================================================
# KEDA ScaledObjects for MLOps Workloads
# =============================================================================

# GPU Workload Scaler - Scale based on pending GPU pods
resource "kubectl_manifest" "keda_gpu_scaledobject" {
  yaml_body = <<-YAML
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: gpu-workload-scaler
      namespace: mlops
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: gpu-worker
      pollingInterval: 15
      cooldownPeriod: 300
      minReplicaCount: 0
      maxReplicaCount: 8
      triggers:
        - type: prometheus
          metadata:
            serverAddress: http://prometheus-kube-prometheus-prometheus.monitoring:9090
            metricName: kube_pod_status_phase
            query: |
              sum(kube_pod_status_phase{phase="Pending",namespace="mlops",pod=~".*gpu.*"})
            threshold: "1"
  YAML

  depends_on = [
    helm_release.keda,
    kubernetes_namespace.mlops,
    helm_release.prometheus_stack
  ]
}

# Training Workload Scaler - Scale based on Argo workflow queue
resource "kubectl_manifest" "keda_training_scaledobject" {
  yaml_body = <<-YAML
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: training-workload-scaler
      namespace: mlops
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: training-worker
      pollingInterval: 30
      cooldownPeriod: 300
      minReplicaCount: 0
      maxReplicaCount: 20
      triggers:
        - type: prometheus
          metadata:
            serverAddress: http://prometheus-kube-prometheus-prometheus.monitoring:9090
            metricName: argo_workflows_queue_depth
            query: |
              sum(argo_workflows_pods_count{phase="Pending"})
            threshold: "2"
  YAML

  depends_on = [
    helm_release.keda,
    kubernetes_namespace.mlops,
    helm_release.prometheus_stack
  ]
}

# Inference Workload Scaler - Scale based on HTTP requests
resource "kubectl_manifest" "keda_inference_scaledobject" {
  yaml_body = <<-YAML
    apiVersion: keda.sh/v1alpha1
    kind: ScaledObject
    metadata:
      name: inference-workload-scaler
      namespace: mlops
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: inference-worker
      pollingInterval: 10
      cooldownPeriod: 60
      minReplicaCount: 1
      maxReplicaCount: 10
      triggers:
        - type: prometheus
          metadata:
            serverAddress: http://prometheus-kube-prometheus-prometheus.monitoring:9090
            metricName: http_requests_per_second
            query: |
              sum(rate(nginx_ingress_controller_requests{namespace="mlops"}[1m]))
            threshold: "100"
  YAML

  depends_on = [
    helm_release.keda,
    kubernetes_namespace.mlops,
    helm_release.prometheus_stack
  ]
}