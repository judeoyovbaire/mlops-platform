# Multi-Tenancy Kyverno Policies
# Policies for namespace isolation and resource governance

# Policy: Enforce resource quotas on new namespaces
resource "kubectl_manifest" "kyverno_require_quota" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-resource-quota
      annotations:
        policies.kyverno.io/title: Require Resource Quota
        policies.kyverno.io/category: Multi-Tenancy
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Generates a default ResourceQuota for new tenant namespaces.
          Prevents resource exhaustion in multi-tenant environments.
    spec:
      rules:
        - name: generate-resourcequota
          match:
            any:
              - resources:
                  kinds:
                    - Namespace
                  selector:
                    matchLabels:
                      mlops.platform/tenant: "*"
          generate:
            apiVersion: v1
            kind: ResourceQuota
            name: default-quota
            namespace: "{{request.object.metadata.name}}"
            synchronize: true
            data:
              spec:
                hard:
                  requests.cpu: "10"
                  requests.memory: "20Gi"
                  limits.cpu: "20"
                  limits.memory: "40Gi"
                  pods: "50"
                  services: "10"
                  persistentvolumeclaims: "10"
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Enforce LimitRange on new namespaces
resource "kubectl_manifest" "kyverno_require_limitrange" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-limit-range
      annotations:
        policies.kyverno.io/title: Require LimitRange
        policies.kyverno.io/category: Multi-Tenancy
        policies.kyverno.io/severity: medium
        policies.kyverno.io/description: >-
          Generates a default LimitRange for new tenant namespaces.
          Sets default resource requests/limits for containers.
    spec:
      rules:
        - name: generate-limitrange
          match:
            any:
              - resources:
                  kinds:
                    - Namespace
                  selector:
                    matchLabels:
                      mlops.platform/tenant: "*"
          generate:
            apiVersion: v1
            kind: LimitRange
            name: default-limits
            namespace: "{{request.object.metadata.name}}"
            synchronize: true
            data:
              spec:
                limits:
                  - type: Container
                    default:
                      cpu: "500m"
                      memory: "512Mi"
                    defaultRequest:
                      cpu: "100m"
                      memory: "128Mi"
                    max:
                      cpu: "4"
                      memory: "8Gi"
                    min:
                      cpu: "50m"
                      memory: "64Mi"
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Prevent cross-namespace resource access
resource "kubectl_manifest" "kyverno_namespace_isolation" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: namespace-isolation
      annotations:
        policies.kyverno.io/title: Namespace Isolation
        policies.kyverno.io/category: Multi-Tenancy
        policies.kyverno.io/severity: high
        policies.kyverno.io/description: >-
          Prevents pods from accessing resources in other tenant namespaces.
          Enforces service account restrictions.
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: restrict-service-account
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaceSelector:
                    matchLabels:
                      mlops.platform/tenant: "*"
          validate:
            message: "Pods in tenant namespaces must use a namespace-specific service account."
            pattern:
              spec:
                serviceAccountName: "?*"
                automountServiceAccountToken: false
  YAML

  depends_on = [helm_release.kyverno]
}

# Policy: Require tenant labels on workloads
resource "kubectl_manifest" "kyverno_require_tenant_labels" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-tenant-labels
      annotations:
        policies.kyverno.io/title: Require Tenant Labels
        policies.kyverno.io/category: Multi-Tenancy
        policies.kyverno.io/severity: low
        policies.kyverno.io/description: >-
          Requires tenant and team labels on workloads for cost allocation
          and resource tracking.
    spec:
      validationFailureAction: Audit
      background: true
      rules:
        - name: require-labels
          match:
            any:
              - resources:
                  kinds:
                    - Deployment
                    - StatefulSet
                    - Job
                  namespaceSelector:
                    matchLabels:
                      mlops.platform/tenant: "*"
          validate:
            message: "Workloads must have 'mlops.platform/team' label for cost tracking."
            pattern:
              metadata:
                labels:
                  mlops.platform/team: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}
