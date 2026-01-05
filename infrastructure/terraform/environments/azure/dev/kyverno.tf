# =============================================================================
# Kyverno - Policy Engine for Kubernetes
# =============================================================================

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = var.helm_kyverno_version
  namespace        = "kyverno"
  create_namespace = true

  set {
    name  = "replicaCount"
    value = "1"
  }

  # Admission controller configuration
  set {
    name  = "admissionController.replicas"
    value = "1"
  }

  depends_on = [module.aks]
}

# =============================================================================
# Kyverno Policies
# =============================================================================

# Require resource limits on all pods
resource "kubectl_manifest" "policy_require_resource_limits" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-resource-limits
      annotations:
        policies.kyverno.io/title: Require Resource Limits
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: medium
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: require-cpu-memory-limits
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kyverno
                    - keda
          validate:
            message: "CPU and memory limits are required"
            pattern:
              spec:
                containers:
                  - resources:
                      limits:
                        memory: "?*"
                        cpu: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}

# Disallow latest tag
resource "kubectl_manifest" "policy_disallow_latest_tag" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-latest-tag
      annotations:
        policies.kyverno.io/title: Disallow Latest Tag
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: medium
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: disallow-latest-tag
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kyverno
          validate:
            message: "Using 'latest' tag is not allowed"
            pattern:
              spec:
                containers:
                  - image: "!*:latest"
  YAML

  depends_on = [helm_release.kyverno]
}

# Require MLOps labels
resource "kubectl_manifest" "policy_require_mlops_labels" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-mlops-labels
      annotations:
        policies.kyverno.io/title: Require MLOps Labels
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: low
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: require-app-label
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
                    - mlflow
                    - argo
          validate:
            message: "The label 'app.kubernetes.io/name' is required"
            pattern:
              metadata:
                labels:
                  app.kubernetes.io/name: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}

# Restrict image registries
resource "kubectl_manifest" "policy_restrict_registries" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: restrict-image-registries
      annotations:
        policies.kyverno.io/title: Restrict Image Registries
        policies.kyverno.io/category: Security
        policies.kyverno.io/severity: high
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: validate-registries
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kyverno
          validate:
            message: "Images must be from approved registries"
            pattern:
              spec:
                containers:
                  - image: >-
                      ghcr.io/* | docker.io/* | gcr.io/* |
                      quay.io/* | mcr.microsoft.com/* |
                      *.azurecr.io/* | registry.k8s.io/*
  YAML

  depends_on = [helm_release.kyverno]
}
