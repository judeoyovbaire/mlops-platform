# Kyverno - Kubernetes Native Policy Engine
# Kyverno provides policy-as-code for Kubernetes using YAML (no Rego required)
# CNCF Incubating project - simpler alternative to OPA/Gatekeeper
# Reference: https://kyverno.io/

# Kyverno namespace with PSA
resource "kubernetes_namespace" "kyverno" {
  metadata {
    name = "kyverno"
    labels = {
      "app.kubernetes.io/name"    = "kyverno"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Kyverno controllers need elevated permissions
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }

  depends_on = [module.eks]
}

# Kyverno Helm release
resource "helm_release" "kyverno" {
  name       = "kyverno"
  repository = "https://kyverno.github.io/kyverno"
  chart      = "kyverno"
  version    = var.helm_kyverno_version
  namespace  = kubernetes_namespace.kyverno.metadata[0].name

  # Increase timeout for CRD installation
  timeout = 600

  # Admission controller configuration
  set {
    name  = "admissionController.replicas"
    value = "2"
  }

  # Background controller for report generation
  set {
    name  = "backgroundController.replicas"
    value = "1"
  }

  # Reports controller
  set {
    name  = "reportsController.replicas"
    value = "1"
  }

  # Cleanup controller
  set {
    name  = "cleanupController.replicas"
    value = "1"
  }

  # Resource limits for admission controller
  set {
    name  = "admissionController.container.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "admissionController.container.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "admissionController.container.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "admissionController.container.resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [
    kubernetes_namespace.kyverno,
    time_sleep.alb_controller_ready
  ]
}

# Kyverno Cluster Policies - MLOps Best Practices

# Policy: Require resource limits on all pods
resource "kubectl_manifest" "kyverno_require_limits" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-resource-limits
      annotations:
        policies.kyverno.io/title: Require Resource Limits
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Pods must specify resource limits to prevent resource exhaustion.
          Critical for ML workloads that can consume unbounded resources.
    spec:
      validationFailureAction: Audit  # Start with Audit, change to Enforce after validation
      background: true
      rules:
        - name: validate-resources
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
                    - mlflow
                    - argo
                    - kserve
          validate:
            message: "CPU and memory limits are required for containers in ML namespaces."
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

# Policy: Disallow latest tag for container images
resource "kubectl_manifest" "kyverno_disallow_latest_tag" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-latest-tag
      annotations:
        policies.kyverno.io/title: Disallow Latest Tag
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Container images must use explicit version tags, not 'latest'.
          Ensures reproducibility of ML model deployments.
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: validate-image-tag
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
                    - kserve
          validate:
            message: "Using 'latest' tag is not allowed. Specify a version tag for reproducibility."
            pattern:
              spec:
                containers:
                  - image: "!*:latest"
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Require labels on pods for MLOps traceability
resource "kubectl_manifest" "kyverno_require_labels" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-mlops-labels
      annotations:
        policies.kyverno.io/title: Require MLOps Labels
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: low
        policies.kyverno.io/description: >-
          Pods in ML namespaces should have labels for tracking model versions,
          experiment IDs, and ownership.
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: check-labels
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
          validate:
            message: "Pods should have 'app.kubernetes.io/name' label for identification."
            pattern:
              metadata:
                labels:
                  app.kubernetes.io/name: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Restrict image registries to trusted sources
resource "kubectl_manifest" "kyverno_restrict_registries" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: restrict-image-registries
      annotations:
        policies.kyverno.io/title: Restrict Image Registries
        policies.kyverno.io/category: Security
        policies.kyverno.io/severity: high
        policies.kyverno.io/description: >-
          Only allow container images from trusted registries.
          Prevents supply chain attacks in ML pipelines.
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
                  namespaces:
                    - mlops
                    - kserve
          validate:
            message: "Images must come from approved registries: ECR, gcr.io, ghcr.io, docker.io, quay.io"
            pattern:
              spec:
                containers:
                  - image: "*.amazonaws.com/* | gcr.io/* | ghcr.io/* | docker.io/* | quay.io/* | kserve/* | seldonio/* | tensorflow/* | pytorch/* | huggingface/*"
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Disallow privileged containers
resource "kubectl_manifest" "kyverno_disallow_privileged" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-privileged-containers
      annotations:
        policies.kyverno.io/title: Disallow Privileged Containers
        policies.kyverno.io/category: Pod Security Standards (Baseline)
        policies.kyverno.io/severity: high
        policies.kyverno.io/description: >-
          Privileged containers are not allowed in ML namespaces.
          Enforced in all environments for security.
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: privileged-containers
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
                    - mlflow
                    - argo
                    - kserve
          validate:
            message: "Privileged mode is not allowed. Set securityContext.privileged to false or omit it."
            deny:
              conditions:
                any:
                  - key: "{{ request.object.spec.containers[].securityContext.privileged || 'false' }}"
                    operator: AnyIn
                    value: ["true"]
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Add default network policy to new namespaces
resource "kubectl_manifest" "kyverno_generate_netpol" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: add-default-networkpolicy
      annotations:
        policies.kyverno.io/title: Add Default Network Policy
        policies.kyverno.io/category: Security
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Automatically generates a default-deny network policy for new namespaces.
          Implements zero-trust networking for ML workloads.
    spec:
      rules:
        - name: default-deny
          match:
            any:
              - resources:
                  kinds:
                    - Namespace
          exclude:
            any:
              - resources:
                  namespaces:
                    - kube-system
                    - kube-public
                    - kube-node-lease
                    - kyverno
                    - cert-manager
          generate:
            apiVersion: networking.k8s.io/v1
            kind: NetworkPolicy
            name: default-deny-ingress
            namespace: "{{request.object.metadata.name}}"
            synchronize: true
            data:
              spec:
                podSelector: {}
                policyTypes:
                  - Ingress
  YAML

  depends_on = [helm_release.kyverno]
}
