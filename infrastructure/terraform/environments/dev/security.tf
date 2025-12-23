# =============================================================================
# Kyverno - Kubernetes Native Policy Engine
# =============================================================================
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
  version    = "3.3.4" # Latest stable as of Dec 2025
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

  depends_on = [kubernetes_namespace.kyverno]
}

# =============================================================================
# Kyverno Cluster Policies - MLOps Best Practices
# =============================================================================

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

# =============================================================================
# Tetragon - eBPF-based Runtime Security
# =============================================================================
# Tetragon provides kernel-level security observability and enforcement
# From the Cilium project - better performance than Falco for enforcement
# Reference: https://tetragon.io/

# Tetragon namespace
resource "kubernetes_namespace" "tetragon" {
  metadata {
    name = "tetragon"
    labels = {
      "app.kubernetes.io/name"    = "tetragon"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Tetragon needs privileged access for eBPF
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }

  depends_on = [module.eks]
}

# Tetragon Helm release
resource "helm_release" "tetragon" {
  name       = "tetragon"
  repository = "https://helm.cilium.io"
  chart      = "tetragon"
  version    = "1.3.0" # Latest stable as of Dec 2025
  namespace  = kubernetes_namespace.tetragon.metadata[0].name

  # Increase timeout for daemonset rollout
  timeout = 600

  # Export events to stdout for log aggregation
  set {
    name  = "tetragon.exportAllowList"
    value = ""
  }

  # Enable Prometheus metrics
  set {
    name  = "tetragon.prometheus.enabled"
    value = "true"
  }

  set {
    name  = "tetragon.prometheus.port"
    value = "2112"
  }

  # Resource configuration
  set {
    name  = "tetragon.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "tetragon.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "tetragon.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "tetragon.resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [kubernetes_namespace.tetragon]
}

# =============================================================================
# Tetragon Tracing Policies - Runtime Security for MLOps
# =============================================================================

# TracingPolicy: Detect sensitive file access in ML containers
resource "kubectl_manifest" "tetragon_sensitive_files" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: sensitive-file-access
      annotations:
        description: Detect access to sensitive files in ML workloads
    spec:
      kprobes:
        - call: "fd_install"
          syscall: false
          args:
            - index: 0
              type: int
            - index: 1
              type: "file"
          selectors:
            - matchArgs:
                - index: 1
                  operator: "Prefix"
                  values:
                    - "/etc/shadow"
                    - "/etc/passwd"
                    - "/root/.ssh"
                    - "/home/*/.ssh"
                    - "/etc/kubernetes"
                    - "/var/run/secrets/kubernetes.io"
              matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: argo
                  operator: In
                - namespace: kserve
                  operator: In
  YAML

  depends_on = [helm_release.tetragon]
}

# TracingPolicy: Detect container escape attempts
resource "kubectl_manifest" "tetragon_container_escape" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: container-escape-detection
      annotations:
        description: Detect potential container escape attempts
    spec:
      kprobes:
        - call: "__x64_sys_ptrace"
          syscall: true
          args:
            - index: 0
              type: int
          selectors:
            - matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: argo
                  operator: In
                - namespace: kserve
                  operator: In
        - call: "__x64_sys_setns"
          syscall: true
          args:
            - index: 0
              type: int
            - index: 1
              type: int
          selectors:
            - matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: argo
                  operator: In
  YAML

  depends_on = [helm_release.tetragon]
}

# TracingPolicy: Monitor network connections from ML pods
resource "kubectl_manifest" "tetragon_network_monitor" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: ml-network-connections
      annotations:
        description: Monitor outbound network connections from ML workloads
    spec:
      kprobes:
        - call: "tcp_connect"
          syscall: false
          args:
            - index: 0
              type: "sock"
          selectors:
            - matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: kserve
                  operator: In
  YAML

  depends_on = [helm_release.tetragon]
}

# TracingPolicy: Detect suspicious process execution
resource "kubectl_manifest" "tetragon_process_execution" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: suspicious-process-execution
      annotations:
        description: Detect execution of suspicious binaries in ML containers
    spec:
      tracepoints:
        - subsystem: "raw_syscalls"
          event: "sys_enter"
          args:
            - index: 4
              type: "syscall64"
          selectors:
            - matchArgs:
                - index: 4
                  operator: "Equal"
                  values:
                    - "59"  # execve syscall number
              matchBinaries:
                - operator: "In"
                  values:
                    - "/bin/sh"
                    - "/bin/bash"
                    - "/usr/bin/wget"
                    - "/usr/bin/curl"
                    - "/usr/bin/nc"
                    - "/usr/bin/ncat"
              matchNamespaces:
                - namespace: kserve
                  operator: In
  YAML

  depends_on = [helm_release.tetragon]
}

# ServiceMonitor for Tetragon metrics (Prometheus integration)
resource "kubectl_manifest" "tetragon_servicemonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: tetragon
      namespace: monitoring
      labels:
        app.kubernetes.io/name: tetragon
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: tetragon
      namespaceSelector:
        matchNames:
          - tetragon
      endpoints:
        - port: metrics
          interval: 30s
          path: /metrics
  YAML

  depends_on = [
    helm_release.tetragon,
    helm_release.prometheus_stack
  ]
}

# =============================================================================
# Multi-Tenancy Kyverno Policies
# =============================================================================
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
