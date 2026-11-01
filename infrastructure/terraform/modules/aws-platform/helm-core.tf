# Core Helm Releases

# AWS Load Balancer Controller: installed; no Ingress objects (UIs via port-forward)
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.helm_aws_lb_controller_version
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = var.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.eks.aws_lb_controller_irsa_role_arn
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = var.eks.vpc_id
    },
  ]
}

# Wait for ALB Controller webhook to be ready
# This prevents race conditions where other helm releases try to create
# Services before the ALB Controller's MutatingWebhookConfiguration is serving
resource "time_sleep" "alb_controller_ready" {
  depends_on      = [helm_release.aws_load_balancer_controller]
  create_duration = "60s"
}

# cert-manager (required by KServe)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.helm_cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    # crds.enabled replaces the deprecated installCRDs; set only one.
    # crds.keep defaults to true (CRDs survive helm uninstall).
    {
      name  = "crds.enabled"
      value = "true"
    },
  ]

  depends_on = [time_sleep.alb_controller_ready]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.helm_argocd_version
  namespace        = "argocd"
  create_namespace = true

  values = concat(
    [file("${path.module}/../../../helm/aws/argocd-values.yaml")],
    [for f in var.argocd_extra_values_files : file(f)],
  )

  depends_on = [time_sleep.alb_controller_ready]
}

# KServe CRDs
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = var.helm_kserve_version # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  depends_on = [helm_release.cert_manager]
}

# KServe Controller. The single `kserve` chart stopped at v0.16.0; from
# v0.17 the controller is `kserve-resources` and the ClusterServingRuntimes
# moved to `kserve-runtime-configs` (below).
resource "helm_release" "kserve_controller" {
  name       = "kserve-controller"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-resources"
  version    = var.helm_kserve_version # Note: KServe OCI charts require 'v' prefix
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  set = [
    # Standard is KServe's current name for RawDeployment (a deprecated alias it
    # still parses). The kserve-resources default is Knative, so this is required.
    {
      name  = "kserve.controller.deploymentMode"
      value = "Standard"
    },
    # kserve-resources defaults to Always from v0.19; the tag is pinned, so do
    # not re-pull from Docker Hub (anonymous rate limit via NAT) on each restart.
    {
      name  = "kserve.controller.imagePullPolicy"
      value = "IfNotPresent"
    },
    # Disable KServe's built-in ingress creation - no Ingress is created; access via port-forward
    {
      name  = "kserve.controller.gateway.disableIngressCreation"
      value = "true"
    },
    {
      name  = "kserve.controller.gateway.disableIstioVirtualHost"
      value = "true"
    },
    # Configure ingress gateway settings
    {
      name  = "kserve.controller.gateway.ingressGateway.gateway"
      value = "kserve/kserve-ingress-gateway"
    },
    {
      name  = "kserve.controller.gateway.ingressGateway.className"
      value = "alb"
    },
    {
      name  = "kserve.controller.gateway.domain"
      value = var.kserve_ingress_domain
    },
  ]

  depends_on = [helm_release.kserve]
}

# KServe ClusterServingRuntimes (mlserver for modelFormat: mlflow, huggingface
# server for modelFormat: huggingface, ...). Without this release those
# InferenceServices have no runtime. The chart renders nothing unless
# servingruntime.enabled is set.
resource "helm_release" "kserve_runtime_configs" {
  name       = "kserve-runtime-configs"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-runtime-configs"
  version    = var.helm_kserve_version
  namespace  = kubernetes_namespace_v1.kserve.metadata[0].name

  set = [
    {
      name  = "kserve.servingruntime.enabled"
      value = "true"
    },
    # Marks the vLLM ClusterServingRuntime spec.disabled (KServe never selects
    # it). It ships with image tag `latest`; the repo's vLLM InferenceServices
    # bring their own pinned container (examples/llm-inference), and
    # disallow-latest-tag would reject pods using this runtime anyway.
    {
      name  = "kserve.servingruntime.vllmserver.disabled"
      value = "true"
    },
  ]

  # The controller serves the ServingRuntime validating webhook
  # (failurePolicy Fail); give cert-manager's cainjector time to write the
  # caBundle after the controller reports ready.
  depends_on = [time_sleep.kserve_webhook_ready]
}

resource "time_sleep" "kserve_webhook_ready" {
  depends_on      = [helm_release.kserve_controller]
  create_duration = "30s"
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = var.helm_mlflow_version
  namespace  = kubernetes_namespace_v1.mlflow.metadata[0].name

  values = [
    templatefile("${path.module}/../../../helm/aws/mlflow-values.yaml", {
      db_host    = split(":", var.eks.mlflow_db_endpoint)[0]
      db_name    = var.eks.mlflow_db_name
      s3_bucket  = var.eks.mlflow_s3_bucket
      aws_region = var.aws_region
    })
  ]

  depends_on = [
    kubernetes_service_account_v1.mlflow,
    kubernetes_secret_v1.mlflow_postgres,
    time_sleep.alb_controller_ready,
    # Network and admission policies first (ADR-017 decision 6).
    terraform_data.platform_baseline_ready,
  ]
}

# Argo Workflows - ML Pipeline Orchestration
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = var.helm_argo_workflows_version
  namespace  = kubernetes_namespace_v1.argo.metadata[0].name

  # Increase timeout for CRD installation
  timeout = 600

  values = [file("${path.module}/../../../helm/aws/argo-workflows-values.yaml")]

  set = [
    # IRSA for workflow pods - MLflow artifact uploads go straight to S3 from
    # the pipeline containers, so the argo-workflow SA needs the role annotation.
    {
      name  = "workflow.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.argo_workflow_irsa.arn
    },
  ]

  depends_on = [time_sleep.alb_controller_ready]
}

# MinIO for pipeline artifact storage (lightweight S3-compatible storage)
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = var.helm_minio_version
  namespace  = kubernetes_namespace_v1.argo.metadata[0].name

  # The chart DEFAULTS to creating a consoleAdmin user with the hardcoded
  # password "console123" - remove it. Credentials are ExternalSecret-managed
  # (existingSecret below); dropping users also removes the extra post-job
  # container that tripped the resource-limits policy.
  values = [yamlencode({ users = [] })]

  set = [
    {
      name  = "mode"
      value = var.minio.mode
    },
    {
      name  = "replicas"
      value = tostring(var.minio.replicas)
    },
    {
      name  = "persistence.size"
      value = var.minio.storage_size
    },
    {
      name  = "persistence.storageClass"
      value = "gp3"
    },
    {
      name  = "resources.requests.memory"
      value = var.minio.memory_request
    },
    {
      name  = "resources.requests.cpu"
      value = var.minio.cpu_request
    },
    # Limits are mandatory: the platform's Kyverno require-resource-limits
    # policy admission-blocks limit-less pods in the argo namespace.
    {
      name  = "resources.limits.memory"
      value = var.minio.memory_limit
    },
    {
      name  = "resources.limits.cpu"
      value = var.minio.cpu_limit
    },
    # Use ExternalSecret-managed credentials (avoids secrets in Helm release metadata)
    {
      name  = "existingSecret"
      value = "minio-credentials"
    },
    # The post-install bucket job must satisfy the platform's own Kyverno
    # require-resource-limits policy (Enforce). NOTE: the chart keys the job
    # container's resources under makeBucketJob.resources - postJob has no
    # resources field (a previous fix targeted it and silently did nothing).
    {
      name  = "makeBucketJob.resources.requests.cpu"
      value = "50m"
    },
    {
      name  = "makeBucketJob.resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "makeBucketJob.resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "makeBucketJob.resources.limits.memory"
      value = "128Mi"
    },
    # Same treatment for the user-provisioning container, should users ever
    # be configured again.
    {
      name  = "makeUserJob.resources.requests.cpu"
      value = "50m"
    },
    {
      name  = "makeUserJob.resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "makeUserJob.resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "makeUserJob.resources.limits.memory"
      value = "128Mi"
    },
    {
      name  = "buckets[0].name"
      value = "mlpipeline"
    },
    {
      name  = "buckets[0].policy"
      value = "none"
    },
  ]

  # Network and admission policies first (ADR-017 decision 6).
  depends_on = [time_sleep.alb_controller_ready, terraform_data.platform_baseline_ready]
}
