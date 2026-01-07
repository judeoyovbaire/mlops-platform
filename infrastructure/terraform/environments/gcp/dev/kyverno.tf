# =============================================================================
# Kyverno Policy Engine
# =============================================================================
# Deploys Kyverno for policy enforcement and multi-tenancy

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  version          = var.helm_kyverno_version
  namespace        = "kyverno"
  create_namespace = true

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "resources.limits.memory"
    value = "512Mi"
  }

  # Admission controller configuration
  set {
    name  = "admissionController.replicas"
    value = "1"
  }

  depends_on = [module.gke]
}

# Wait for Kyverno CRDs to be ready
resource "time_sleep" "wait_for_kyverno" {
  depends_on      = [helm_release.kyverno]
  create_duration = "30s"
}

# =============================================================================
# Kyverno Policies
# =============================================================================

# Require resource limits on all pods
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
      validationFailureAction: Audit
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
            message: "CPU and memory limits are required for containers"
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

# Require team labels for cost tracking
resource "kubectl_manifest" "require_team_labels" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-team-labels
      annotations:
        policies.kyverno.io/title: Require Team Labels
        policies.kyverno.io/category: Best Practices
        policies.kyverno.io/severity: low
        policies.kyverno.io/description: >-
          Pods in tenant namespaces must have team labels for cost tracking.
    spec:
      validationFailureAction: Audit
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
            message: "The label 'team' is required for cost tracking"
            pattern:
              metadata:
                labels:
                  team: "?*"
  YAML

  depends_on = [time_sleep.wait_for_kyverno]
}

# Disallow privileged containers
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
            message: "Privileged mode is not allowed"
            pattern:
              spec:
                containers:
                  - securityContext:
                      privileged: false
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
