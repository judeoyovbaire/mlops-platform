# State migrations for the aws-platform module extraction.
# Every resource that moved from this root module into
# module.platform keeps its state identity - without these blocks
# an existing environment would plan destroy/recreate for the
# entire platform layer.

moved {
  from = aws_iam_policy.external_secrets_sm
  to   = module.platform.aws_iam_policy.external_secrets_sm
}

moved {
  from = aws_ssm_parameter.grafana_admin_password
  to   = module.platform.aws_ssm_parameter.grafana_admin_password
}

moved {
  from = helm_release.alloy
  to   = module.platform.helm_release.alloy
}

moved {
  from = helm_release.argo_events
  to   = module.platform.helm_release.argo_events
}

moved {
  from = helm_release.argo_rollouts
  to   = module.platform.helm_release.argo_rollouts
}

moved {
  from = helm_release.argo_workflows
  to   = module.platform.helm_release.argo_workflows
}

moved {
  from = helm_release.argocd
  to   = module.platform.helm_release.argocd
}

moved {
  from = helm_release.aws_load_balancer_controller
  to   = module.platform.helm_release.aws_load_balancer_controller
}

moved {
  from = helm_release.cert_manager
  to   = module.platform.helm_release.cert_manager
}

moved {
  from = helm_release.dcgm_exporter
  to   = module.platform.helm_release.dcgm_exporter
}

moved {
  from = helm_release.external_secrets
  to   = module.platform.helm_release.external_secrets
}

moved {
  from = helm_release.karpenter
  to   = module.platform.helm_release.karpenter
}

moved {
  from = helm_release.kserve
  to   = module.platform.helm_release.kserve
}

moved {
  from = helm_release.kserve_controller
  to   = module.platform.helm_release.kserve_controller
}

moved {
  from = helm_release.kyverno
  to   = module.platform.helm_release.kyverno
}

moved {
  from = helm_release.loki
  to   = module.platform.helm_release.loki
}

moved {
  from = helm_release.minio
  to   = module.platform.helm_release.minio
}

moved {
  from = helm_release.mlflow
  to   = module.platform.helm_release.mlflow
}

moved {
  from = helm_release.opencost
  to   = module.platform.helm_release.opencost
}

moved {
  from = helm_release.otel_collector
  to   = module.platform.helm_release.otel_collector
}

moved {
  from = helm_release.prometheus_stack
  to   = module.platform.helm_release.prometheus_stack
}

moved {
  from = helm_release.tempo
  to   = module.platform.helm_release.tempo
}

moved {
  from = helm_release.tetragon
  to   = module.platform.helm_release.tetragon
}

moved {
  from = kubectl_manifest.alertmanager_slack_external_secret
  to   = module.platform.kubectl_manifest.alertmanager_slack_external_secret
}

moved {
  from = kubectl_manifest.argo_minio_external_secret
  to   = module.platform.kubectl_manifest.argo_minio_external_secret
}

moved {
  from = kubectl_manifest.cluster_secret_store
  to   = module.platform.kubectl_manifest.cluster_secret_store
}

moved {
  from = kubectl_manifest.grafana_cloud_cost_dashboard
  to   = module.platform.kubectl_manifest.grafana_cloud_cost_dashboard
}

moved {
  from = kubectl_manifest.grafana_mlops_overview_dashboard
  to   = module.platform.kubectl_manifest.grafana_mlops_overview_dashboard
}

moved {
  from = kubectl_manifest.karpenter_default_nodeclass
  to   = module.platform.kubectl_manifest.karpenter_default_nodeclass
}

moved {
  from = kubectl_manifest.karpenter_general_nodepool
  to   = module.platform.kubectl_manifest.karpenter_general_nodepool
}

moved {
  from = kubectl_manifest.karpenter_gpu_nodeclass
  to   = module.platform.kubectl_manifest.karpenter_gpu_nodeclass
}

moved {
  from = kubectl_manifest.karpenter_gpu_nodepool
  to   = module.platform.kubectl_manifest.karpenter_gpu_nodepool
}

moved {
  from = kubectl_manifest.karpenter_training_nodepool
  to   = module.platform.kubectl_manifest.karpenter_training_nodepool
}

moved {
  from = kubectl_manifest.kyverno_disallow_latest_tag
  to   = module.platform.kubectl_manifest.kyverno_disallow_latest_tag
}

moved {
  from = kubectl_manifest.kyverno_disallow_privileged
  to   = module.platform.kubectl_manifest.kyverno_disallow_privileged
}

moved {
  from = kubectl_manifest.kyverno_generate_netpol
  to   = module.platform.kubectl_manifest.kyverno_generate_netpol
}

moved {
  from = kubectl_manifest.kyverno_namespace_isolation
  to   = module.platform.kubectl_manifest.kyverno_namespace_isolation
}

moved {
  from = kubectl_manifest.kyverno_require_labels
  to   = module.platform.kubectl_manifest.kyverno_require_labels
}

moved {
  from = kubectl_manifest.kyverno_require_limitrange
  to   = module.platform.kubectl_manifest.kyverno_require_limitrange
}

moved {
  from = kubectl_manifest.kyverno_require_limits
  to   = module.platform.kubectl_manifest.kyverno_require_limits
}

moved {
  from = kubectl_manifest.kyverno_require_quota
  to   = module.platform.kubectl_manifest.kyverno_require_quota
}

moved {
  from = kubectl_manifest.kyverno_require_tenant_labels
  to   = module.platform.kubectl_manifest.kyverno_require_tenant_labels
}

moved {
  from = kubectl_manifest.kyverno_restrict_registries
  to   = module.platform.kubectl_manifest.kyverno_restrict_registries
}

moved {
  from = kubectl_manifest.mlflow_external_secret
  to   = module.platform.kubectl_manifest.mlflow_external_secret
}

moved {
  from = kubectl_manifest.network_policies
  to   = module.platform.kubectl_manifest.network_policies
}

moved {
  from = kubectl_manifest.tetragon_container_escape
  to   = module.platform.kubectl_manifest.tetragon_container_escape
}

moved {
  from = kubectl_manifest.tetragon_network_monitor
  to   = module.platform.kubectl_manifest.tetragon_network_monitor
}

moved {
  from = kubectl_manifest.tetragon_process_execution
  to   = module.platform.kubectl_manifest.tetragon_process_execution
}

moved {
  from = kubectl_manifest.tetragon_sensitive_files
  to   = module.platform.kubectl_manifest.tetragon_sensitive_files
}

moved {
  from = kubectl_manifest.tetragon_servicemonitor
  to   = module.platform.kubectl_manifest.tetragon_servicemonitor
}

moved {
  from = kubernetes_annotations.gp2_not_default
  to   = module.platform.kubernetes_annotations.gp2_not_default
}

moved {
  from = kubernetes_namespace.argo
  to   = module.platform.kubernetes_namespace.argo
}

moved {
  from = kubernetes_namespace.karpenter
  to   = module.platform.kubernetes_namespace.karpenter
}

moved {
  from = kubernetes_namespace.kserve
  to   = module.platform.kubernetes_namespace.kserve
}

moved {
  from = kubernetes_namespace.kyverno
  to   = module.platform.kubernetes_namespace.kyverno
}

moved {
  from = kubernetes_namespace.mlflow
  to   = module.platform.kubernetes_namespace.mlflow
}

moved {
  from = kubernetes_namespace.mlops
  to   = module.platform.kubernetes_namespace.mlops
}

moved {
  from = kubernetes_namespace.monitoring
  to   = module.platform.kubernetes_namespace.monitoring
}

moved {
  from = kubernetes_namespace.tetragon
  to   = module.platform.kubernetes_namespace.tetragon
}

moved {
  from = kubernetes_secret.mlflow_postgres
  to   = module.platform.kubernetes_secret.mlflow_postgres
}

moved {
  from = kubernetes_service_account.mlflow
  to   = module.platform.kubernetes_service_account.mlflow
}

moved {
  from = kubernetes_storage_class.gp3
  to   = module.platform.kubernetes_storage_class.gp3
}

moved {
  from = module.external_secrets_irsa
  to   = module.platform.module.external_secrets_irsa
}

moved {
  from = null_resource.karpenter_cleanup
  to   = module.platform.null_resource.karpenter_cleanup
}

moved {
  from = time_sleep.alb_controller_ready
  to   = module.platform.time_sleep.alb_controller_ready
}
