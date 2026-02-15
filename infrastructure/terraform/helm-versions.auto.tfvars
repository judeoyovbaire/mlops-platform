# Shared Helm Chart Versions
# Single source of truth — symlinked into each environment directory.
# Cloud-specific versions (AWS LB Controller, Karpenter, KEDA, NGINX Ingress)
# remain in their respective environment variables.tf files.

helm_cert_manager_version     = "v1.19.3"
helm_argocd_version           = "9.4.2"
helm_kserve_version           = "v0.16.0"
helm_mlflow_version           = "1.8.1"
helm_argo_workflows_version   = "0.47.3"
helm_minio_version            = "5.4.0"
helm_prometheus_stack_version = "81.6.9"
helm_kyverno_version          = "3.6.2"
helm_tetragon_version         = "1.6.0"
helm_external_secrets_version = "1.2.1"
helm_loki_version             = "6.24.0"
helm_tempo_version            = "1.15.0"
helm_otel_collector_version   = "0.108.0"
helm_alloy_version            = "0.12.0"
