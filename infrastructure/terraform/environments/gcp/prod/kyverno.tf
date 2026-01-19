# =============================================================================
# Kyverno Policy Engine - Production
# =============================================================================
# Deploys Kyverno for policy enforcement and multi-tenancy

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  version          = var.helm_kyverno_version
  namespace        = "kyverno"
  create_namespace = true

  # Production: Higher replica count for HA
  set {
    name  = "replicaCount"
    value = "3"
  }

  set {
    name  = "resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.limits.memory"
    value = "1Gi"
  }

  # Admission controller configuration - Production HA
  set {
    name  = "admissionController.replicas"
    value = "3"
  }

  depends_on = [module.gke]
}

# Wait for Kyverno CRDs to be ready
resource "time_sleep" "wait_for_kyverno" {
  depends_on      = [helm_release.kyverno]
  create_duration = "30s"
}

# =============================================================================
# Kyverno Policies - Production (Stricter Enforcement)
# =============================================================================

# Require resource limits on all pods - ENFORCED in production
resource "kubectl_manifest" "require_resource_limits" {
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
          Containers must have resource limits set.
    spec:
      validationFailureAction: Enforce
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
          validate:
            message: "CPU and memory limits are required for containers in production"
            pattern:
              spec:
                containers:
                  - resources:
                      limits:
                        memory: "?*"
                        cpu: "?*"
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}

# Require team labels for cost tracking - ENFORCED in production
resource "kubectl_manifest" "require_team_labels" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-team-labels
      annotations:
        policies.kyverno.io/title: Require Team Labels
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Pods in tenant namespaces must have team labels for cost tracking.
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-team-label
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mlops
          validate:
            message: "The label 'team' is required for cost tracking in production"
            pattern:
              metadata:
                labels:
                  team: "?*"
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}

# Disallow privileged containers - ENFORCED in production
resource "kubectl_manifest" "disallow_privileged" {
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
          Privileged containers are not allowed in tenant namespaces.
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
            message: "Privileged mode is not allowed in production. Set securityContext.privileged to false or omit it."
            deny:
              conditions:
                any:
                  - key: "{{ request.object.spec.containers[].securityContext.privileged || 'false' }}"
                    operator: AnyIn
                    value: ["true"]
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}

# Generate default network policies for namespaces
resource "kubectl_manifest" "generate_network_policies" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: generate-default-network-policy
      annotations:
        policies.kyverno.io/title: Generate Default Network Policy
        policies.kyverno.io/category: Multi-Tenancy
        policies.kyverno.io/description: >-
          Generates a default deny-all network policy for new namespaces with the 'tenant' label.
    spec:
      rules:
        - name: generate-network-policy
          match:
            any:
              - resources:
                  kinds:
                    - Namespace
          generate:
            apiVersion: networking.k8s.io/v1
            kind: NetworkPolicy
            name: default-deny
            namespace: "{{ request.object.metadata.name }}"
            data:
              spec:
                podSelector: {}
                policyTypes:
                  - Ingress
                  - Egress
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}

# Disallow latest tag in production
resource "kubectl_manifest" "disallow_latest_tag" {
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
          Using 'latest' tag is not allowed in production for reproducibility.
    spec:
      validationFailureAction: Enforce
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
                    - mlflow
                    - kserve
          validate:
            message: "Using 'latest' image tag is not allowed in production. Please use a specific version tag."
            pattern:
              spec:
                containers:
                  - image: "!*:latest"
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}
