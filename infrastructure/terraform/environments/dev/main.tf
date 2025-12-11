# Development Environment - MLOps Platform on EKS

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state backend - created by bootstrap module
  backend "s3" {
    bucket         = "mlops-platform-tfstate-183590992229"
    key            = "mlops-platform/dev/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "mlops-platform-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "mlops-platform"
      ManagedBy   = "terraform"
    }
  }
}

# Kubernetes provider configuration (after cluster creation)
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# kubectl provider for CRD-based resources (handles cluster-not-exist scenario during plan)
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# =============================================================================
# Secret Generation and SSM Parameter Store
# =============================================================================

# Generate secure random passwords
resource "random_password" "mlflow_db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "pipeline_db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "minio" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "argocd_admin" {
  length  = 24
  special = false
}

# Store secrets in AWS SSM Parameter Store (SecureString)
resource "aws_ssm_parameter" "mlflow_db_password" {
  name        = "/${var.cluster_name}/mlflow/db-password"
  description = "MLflow PostgreSQL database password"
  type        = "SecureString"
  value       = random_password.mlflow_db.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

resource "aws_ssm_parameter" "pipeline_db_password" {
  name        = "/${var.cluster_name}/kubeflow/db-password"
  description = "Kubeflow Pipelines MySQL database password"
  type        = "SecureString"
  value       = random_password.pipeline_db.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

resource "aws_ssm_parameter" "minio_root_password" {
  name        = "/${var.cluster_name}/minio/root-password"
  description = "MinIO root password"
  type        = "SecureString"
  value       = random_password.minio.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

resource "aws_ssm_parameter" "argocd_admin_password" {
  name        = "/${var.cluster_name}/argocd/admin-password"
  description = "ArgoCD admin password"
  type        = "SecureString"
  value       = random_password.argocd_admin.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}

# Store non-secret configuration in SSM for easy access
resource "aws_ssm_parameter" "cluster_endpoint" {
  name        = "/${var.cluster_name}/cluster/endpoint"
  description = "EKS cluster endpoint"
  type        = "String"
  value       = module.eks.cluster_endpoint

  tags = var.tags
}

resource "aws_ssm_parameter" "cluster_name_param" {
  name        = "/${var.cluster_name}/cluster/name"
  description = "EKS cluster name"
  type        = "String"
  value       = module.eks.cluster_name

  tags = var.tags
}

# EKS Cluster
module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_cidr        = var.vpc_cidr
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Cost optimization for dev: single NAT gateway
  single_nat_gateway = true

  # General nodes for platform services
  general_instance_types = ["t3.large"]
  general_min_size       = 2
  general_max_size       = 4
  general_desired_size   = 2

  # Training nodes (scale to zero when not in use)
  training_instance_types = ["c5.2xlarge"]
  training_capacity_type  = "SPOT"
  training_min_size       = 0
  training_max_size       = 5
  training_desired_size   = 0

  # GPU nodes (scale to zero when not in use)
  gpu_instance_types = ["g4dn.xlarge"]
  gpu_capacity_type  = "SPOT"
  gpu_min_size       = 0
  gpu_max_size       = 2
  gpu_desired_size   = 0

  # MLflow database (uses auto-generated password)
  mlflow_db_instance_class = "db.t3.small"
  mlflow_db_password       = random_password.mlflow_db.result

  tags = var.tags
}

# Kubernetes namespaces
resource "kubernetes_namespace" "mlops" {
  metadata {
    name = "mlops"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "mlflow" {
  metadata {
    name = "mlflow"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "kubeflow" {
  metadata {
    name = "kubeflow"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "kserve" {
  metadata {
    name = "kserve"
    labels = {
      "app.kubernetes.io/name"    = "mlops-platform"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

# MLflow secrets (using generated password)
resource "kubernetes_secret" "mlflow_postgres" {
  metadata {
    name      = "mlflow-postgres"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  data = {
    username = "mlflow"
    password = random_password.mlflow_db.result
  }

  depends_on = [kubernetes_namespace.mlflow]
}

resource "kubernetes_secret" "mlflow_s3" {
  metadata {
    name      = "mlflow-s3"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
  }

  # Using IRSA, so no need for static credentials
  # These are placeholders - actual auth uses service account
  data = {
    access-key = "use-irsa"
    secret-key = "use-irsa"
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# Service account for MLflow with IRSA
resource "kubernetes_service_account" "mlflow" {
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace.mlflow.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.eks.mlflow_irsa_role_arn
    }
  }

  depends_on = [kubernetes_namespace.mlflow]
}

# =============================================================================
# Helm Releases
# =============================================================================

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.16.0"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.aws_lb_controller_irsa_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.eks.vpc_id
  }

  depends_on = [module.eks]
}

# cert-manager (required by KServe)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.19.1"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.9.0"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/../../../helm/aws/argocd-values.yaml")]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# KServe CRDs
resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve-crd"
  version    = "0.16.0"
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  depends_on = [helm_release.cert_manager]
}

# KServe Controller
resource "helm_release" "kserve_controller" {
  name       = "kserve-controller"
  repository = "oci://ghcr.io/kserve/charts"
  chart      = "kserve"
  version    = "0.16.0"
  namespace  = kubernetes_namespace.kserve.metadata[0].name

  set {
    name  = "kserve.controller.deploymentMode"
    value = "RawDeployment"
  }

  depends_on = [helm_release.kserve]
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "0.7.19"
  namespace  = kubernetes_namespace.mlflow.metadata[0].name

  values = [
    templatefile("${path.module}/../../../helm/aws/mlflow-values.yaml", {
      db_host    = split(":", module.eks.mlflow_db_endpoint)[0]
      db_name    = module.eks.mlflow_db_name
      s3_bucket  = module.eks.mlflow_s3_bucket
      aws_region = var.aws_region
    })
  ]

  depends_on = [
    kubernetes_service_account.mlflow,
    kubernetes_secret.mlflow_postgres,
    helm_release.aws_load_balancer_controller
  ]
}

# =============================================================================
# Kubeflow Pipelines
# =============================================================================

# Kubeflow Pipelines (standalone mode - no full Kubeflow installation required)
resource "helm_release" "kubeflow_pipelines" {
  name       = "kubeflow-pipelines"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = "0.46.1"
  namespace  = kubernetes_namespace.kubeflow.metadata[0].name

  # Argo Workflows is the execution engine for Kubeflow Pipelines
  values = [file("${path.module}/../../../helm/aws/argo-workflows-values.yaml")]

  depends_on = [module.eks]
}

# MinIO for pipeline artifact storage (lightweight S3-compatible storage)
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.4.0"
  namespace  = kubernetes_namespace.kubeflow.metadata[0].name

  set {
    name  = "mode"
    value = "standalone"
  }

  set {
    name  = "replicas"
    value = "1"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }

  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "rootUser"
    value = "minio"
  }

  # Use generated password from SSM
  set {
    name  = "rootPassword"
    value = random_password.minio.result
  }

  set {
    name  = "buckets[0].name"
    value = "mlpipeline"
  }

  set {
    name  = "buckets[0].policy"
    value = "none"
  }

  depends_on = [module.eks]
}

# MySQL for Kubeflow Pipelines metadata
resource "helm_release" "mysql" {
  name       = "mysql"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "mysql"
  version    = "14.0.3"
  namespace  = kubernetes_namespace.kubeflow.metadata[0].name

  # Use generated passwords
  set {
    name  = "auth.rootPassword"
    value = random_password.pipeline_db.result
  }

  set {
    name  = "auth.database"
    value = "mlpipeline"
  }

  set {
    name  = "auth.username"
    value = "mlpipeline"
  }

  set {
    name  = "auth.password"
    value = random_password.pipeline_db.result
  }

  set {
    name  = "primary.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "primary.resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "primary.resources.limits.memory"
    value = "2Gi"
  }

  # CPU limits
  set {
    name  = "primary.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "primary.resources.limits.cpu"
    value = "1"
  }

  depends_on = [module.eks]
}

# =============================================================================
# Karpenter - GPU Autoscaling
# =============================================================================

# Karpenter namespace
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = {
      "app.kubernetes.io/name"    = "karpenter"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

# Karpenter Helm release
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.5.6"
  namespace  = kubernetes_namespace.karpenter.metadata[0].name

  set {
    name  = "settings.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.karpenter_irsa_role_arn
  }

  # Resource requests
  set {
    name  = "controller.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }

  # Resource limits (sized for medium cluster)
  set {
    name  = "controller.resources.limits.cpu"
    value = "2"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "2Gi"
  }

  depends_on = [
    kubernetes_namespace.karpenter,
    module.eks
  ]
}

# Karpenter NodePool for GPU workloads
resource "kubectl_manifest" "karpenter_gpu_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gpu-workloads
    spec:
      template:
        metadata:
          labels:
            node-type: gpu
            karpenter.sh/capacity-type: spot
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: gpu
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["g", "p"]
            - key: karpenter.k8s.aws/instance-family
              operator: In
              values: ["g4dn", "g5", "p3", "p4d"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          taints:
            - key: nvidia.com/gpu
              value: "true"
              effect: NoSchedule
      limits:
        cpu: "100"
        memory: 400Gi
        nvidia.com/gpu: "8"
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
      # Cost optimization: terminate GPU nodes after 4 hours to prevent runaway costs
      expireAfter: 4h
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool for training workloads (CPU)
resource "kubectl_manifest" "karpenter_training_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: training-workloads
    spec:
      template:
        metadata:
          labels:
            node-type: training
            karpenter.sh/capacity-type: spot
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-size
              operator: In
              values: ["xlarge", "2xlarge", "4xlarge"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          taints:
            - key: workload
              value: training
              effect: NoSchedule
      limits:
        cpu: "200"
        memory: 800Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter EC2NodeClass for GPU instances
resource "kubectl_manifest" "karpenter_gpu_nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: gpu
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${module.eks.karpenter_node_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            deleteOnTermination: true
            encrypted: true
      tags:
        Environment: dev
        Project: mlops-platform
        NodeType: gpu
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter EC2NodeClass for default/training instances
resource "kubectl_manifest" "karpenter_default_nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${module.eks.karpenter_node_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            deleteOnTermination: true
            encrypted: true
      tags:
        Environment: dev
        Project: mlops-platform
        NodeType: training
  YAML

  depends_on = [helm_release.karpenter]
}

# =============================================================================
# External Secrets Operator - SSM to K8s Secret Sync
# =============================================================================

# IRSA for External Secrets Operator
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    ssm_read = aws_iam_policy.external_secrets_ssm.arn
  }
}

# IAM policy for External Secrets to read from SSM
resource "aws_iam_policy" "external_secrets_ssm" {
  name        = "${var.cluster_name}-external-secrets-ssm"
  description = "Allow External Secrets Operator to read from SSM Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# External Secrets Operator Helm release
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "1.1.1" # Latest stable
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.iam_role_arn
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  depends_on = [module.eks]
}

# ClusterSecretStore for AWS SSM Parameter Store
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-ssm
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

# External Secret for MLflow (syncs SSM to K8s Secret)
resource "kubectl_manifest" "mlflow_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: mlflow-db-credentials
      namespace: mlflow
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-ssm
        kind: ClusterSecretStore
      target:
        name: mlflow-db-credentials
        creationPolicy: Owner
      data:
        - secretKey: password
          remoteRef:
            key: /${var.cluster_name}/mlflow/db-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.mlflow
  ]
}

# External Secret for Kubeflow/MinIO
resource "kubectl_manifest" "kubeflow_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: pipeline-credentials
      namespace: kubeflow
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: aws-ssm
        kind: ClusterSecretStore
      target:
        name: pipeline-credentials
        creationPolicy: Owner
      data:
        - secretKey: mysql-password
          remoteRef:
            key: /${var.cluster_name}/kubeflow/db-password
        - secretKey: minio-password
          remoteRef:
            key: /${var.cluster_name}/minio/root-password
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.kubeflow
  ]
}

# =============================================================================
# Observability Stack - Prometheus & Grafana
# =============================================================================

# Monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/name"    = "monitoring"
      "app.kubernetes.io/part-of" = "mlops-platform"
    }
  }

  depends_on = [module.eks]
}

# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "72.6.2"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/../../../helm/aws/prometheus-stack-values.yaml")]

  # Increase timeout for CRD installation
  timeout = 900

  set {
    name  = "grafana.adminPassword"
    value = random_password.argocd_admin.result # Reuse generated password
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.aws_load_balancer_controller
  ]
}

# Store Grafana password in SSM
resource "aws_ssm_parameter" "grafana_admin_password" {
  name        = "/${var.cluster_name}/grafana/admin-password"
  description = "Grafana admin password"
  type        = "SecureString"
  value       = random_password.argocd_admin.result
  key_id      = "alias/aws/ssm"

  tags = var.tags
}