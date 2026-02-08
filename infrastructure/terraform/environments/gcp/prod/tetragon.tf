# Tetragon Runtime Security - Production
# Deploys Tetragon for eBPF-based runtime security monitoring

resource "helm_release" "tetragon" {
  name             = "tetragon"
  repository       = "https://helm.cilium.io"
  chart            = "tetragon"
  version          = var.helm_tetragon_version
  namespace        = "kube-system"
  create_namespace = false

  # Export metrics for Prometheus
  set {
    name  = "tetragon.prometheus.enabled"
    value = "true"
  }

  # ServiceMonitor disabled - CRD not available until prometheus-stack installs
  set {
    name  = "tetragon.prometheus.serviceMonitor.enabled"
    value = "false"
  }

  # Production: Higher resource limits
  set {
    name  = "tetragon.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "tetragon.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "tetragon.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "tetragon.resources.limits.memory"
    value = "1Gi"
  }

  # Enable default tracing policies
  set {
    name  = "tetragonOperator.enabled"
    value = "true"
  }

  depends_on = [module.gke]
}

# Tetragon Tracing Policies - Production

# Wait for Tetragon CRDs
resource "time_sleep" "wait_for_tetragon" {
  depends_on      = [helm_release.tetragon]
  create_duration = "30s"
}

# Detect sensitive file access
resource "kubectl_manifest" "tetragon_sensitive_file_access" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: sensitive-file-access
    spec:
      kprobes:
        - call: "fd_install"
          syscall: false
          args:
            - index: 0
              type: "int"
            - index: 1
              type: "file"
          selectors:
            - matchArgs:
                - index: 1
                  operator: "Prefix"
                  values:
                    - "/etc/shadow"
                    - "/etc/passwd"
                    - "/etc/kubernetes"
                    - "/var/run/secrets"
  YAML

  depends_on = [time_sleep.wait_for_tetragon]
}

# Detect network connections to external IPs
resource "kubectl_manifest" "tetragon_network_egress" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: network-egress-monitoring
    spec:
      kprobes:
        - call: "tcp_connect"
          syscall: false
          args:
            - index: 0
              type: "sock"
  YAML

  depends_on = [time_sleep.wait_for_tetragon]
}

# Detect privilege escalation attempts
resource "kubectl_manifest" "tetragon_privilege_escalation" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: privilege-escalation
    spec:
      kprobes:
        - call: "sys_setuid"
          syscall: true
          args:
            - index: 0
              type: "int"
        - call: "sys_setgid"
          syscall: true
          args:
            - index: 0
              type: "int"
  YAML

  depends_on = [time_sleep.wait_for_tetragon]
}

# Detect process execution in sensitive namespaces
resource "kubectl_manifest" "tetragon_process_exec" {
  yaml_body = <<-YAML
    apiVersion: cilium.io/v1alpha1
    kind: TracingPolicy
    metadata:
      name: process-exec-monitoring
    spec:
      kprobes:
        - call: "sys_execve"
          syscall: true
          args:
            - index: 0
              type: "string"
          selectors:
            - matchNamespaces:
                - namespace: mlops
                  operator: In
                - namespace: mlflow
                  operator: In
                - namespace: kserve
                  operator: In
  YAML

  depends_on = [time_sleep.wait_for_tetragon]
}
