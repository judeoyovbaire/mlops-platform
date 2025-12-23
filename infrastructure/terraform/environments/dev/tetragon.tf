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

  depends_on = [
    kubernetes_namespace.tetragon,
    time_sleep.alb_controller_ready
  ]
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
        - call: "__x64_sys_setns"
          syscall: true
          args:
            - index: 0
              type: int
            - index: 1
              type: int
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
