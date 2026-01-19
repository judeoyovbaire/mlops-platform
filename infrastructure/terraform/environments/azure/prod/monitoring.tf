# =============================================================================
# Monitoring Stack - Prometheus + Grafana
# =============================================================================

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

# =============================================================================
# ServiceMonitors for MLOps Components
# =============================================================================

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
