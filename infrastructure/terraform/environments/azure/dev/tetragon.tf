# =============================================================================
# Tetragon - Runtime Security and Observability
# =============================================================================

resource "helm_release" "tetragon" {
  name             = "tetragon"
  repository       = "https://helm.cilium.io"
  chart            = "tetragon"
  version          = var.helm_tetragon_version
  namespace        = "tetragon"
  create_namespace = true

  set {
    name  = "tetragon.enablePolicyFilter"
    value = "true"
  }

  set {
    name  = "tetragon.enableProcessCredentials"
    value = "true"
  }

  depends_on = [module.aks]
}

# =============================================================================
# Tetragon Tracing Policies
# =============================================================================

# Monitor file access in sensitive directories
resource "kubectl_manifest" "tetragon_file_access_policy" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: monitor-sensitive-file-access
    spec:
      kprobes:
        - call: "security_file_open"
          syscall: false
          args:
            - index: 0
              type: "file"
          selectors:
            - matchArgs:
                - index: 0
                  operator: "Prefix"
                  values:
                    - "/etc/passwd"
                    - "/etc/shadow"
                    - "/etc/kubernetes"
                    - "/var/run/secrets"
  YAML

  depends_on = [helm_release.tetragon]
}

# Monitor network connections
resource "kubectl_manifest" "tetragon_network_policy" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: monitor-network-connections
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

# Monitor process execution in MLOps namespace
resource "kubectl_manifest" "tetragon_exec_policy" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: monitor-process-execution
    spec:
      tracepoints:
        - subsystem: "syscalls"
          event: "sys_enter_execve"
          args:
            - index: 1
              type: "string"
          selectors:
            - matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: mlflow
                  operator: In
  YAML

  depends_on = [helm_release.tetragon]
}
