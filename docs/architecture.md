# Architecture Deep Dive

## Overview

The MLOps Platform is designed to provide a complete ML lifecycle management solution on AWS EKS. It follows cloud-native principles and enables teams to build, train, deploy, and monitor ML models at scale.

## Core Components

### 1. Argo Workflows

Argo Workflows orchestrates ML workflows as directed acyclic graphs (DAGs). Each step in a pipeline runs as a container, enabling reproducibility and scalability.

**Key Features:**
- Kubernetes-native workflow engine
- DAG and step-based workflow definitions
- Artifact passing between steps
- Caching and memoization for faster iteration
- Integration with MLflow for experiment tracking

```yaml
# Example workflow structure
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: ml-training-pipeline
spec:
  entrypoint: ml-pipeline
  templates:
    - name: ml-pipeline
      dag:
        tasks:
          - name: data-ingestion
          - name: data-validation
            dependencies: [data-ingestion]
          - name: feature-engineering
            dependencies: [data-validation]
          - name: model-training
            dependencies: [feature-engineering]
          - name: model-evaluation
            dependencies: [model-training]
```

### 2. MLflow 3.x

MLflow provides the experiment tracking and model registry capabilities.

**Components:**
- **Tracking Server**: Logs parameters, metrics, and artifacts
- **Model Registry**: Central repository for model versions with aliases
- **Backend Store**: RDS PostgreSQL for metadata
- **Artifact Store**: S3 for model artifacts

**New in MLflow 3.x:**
- Model aliases replace deprecated staging workflow
- Native GenAI/LLM support (prompt versioning, agent tracing)
- Model Context Protocol (MCP) server integration

**Architecture:**
```
┌─────────────────┐     ┌─────────────────┐
│  Training Job   │────▶│  MLflow Server  │
└─────────────────┘     └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
              ┌─────▼─────┐           ┌───────▼───────┐
              │ RDS       │           │  S3 Bucket    │
              │ PostgreSQL│           │  (artifacts)  │
              └───────────┘           └───────────────┘
```

### 3. KServe

KServe (CNCF Incubating) handles model serving with advanced deployment strategies. It replaced Seldon Core due to licensing changes (Seldon moved to BSL 1.1 in Jan 2024).

**Features:**
- RawDeployment mode (no Knative required)
- Canary deployments with traffic splitting
- Native support for sklearn, PyTorch, TensorFlow, vLLM
- MLflow model integration
- Autoscaling with HPA/KEDA

**Deployment Example:**
```yaml
# Canary Deployment Configuration
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: sklearn-iris-canary
spec:
  predictor:
    canaryTrafficPercent: 10
    model:
      modelFormat:
        name: sklearn
      storageUri: s3://models/sklearn/iris
```

### 4. LLM Inference with vLLM

The platform includes support for LLM inference using vLLM on GPU nodes:

**Features:**
- PagedAttention for efficient memory management
- Continuous batching for high throughput
- OpenAI-compatible API endpoints
- Scale-to-zero for cost optimization

**Example Deployment:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llm-mistral
spec:
  predictor:
    containers:
      - name: kserve-container
        image: vllm/vllm-openai:v0.8.0
        args:
          - --model=mistralai/Mistral-7B-Instruct-v0.2
          - --max-model-len=4096
          - --gpu-memory-utilization=0.9
        resources:
          limits:
            nvidia.com/gpu: "1"
```

**Included Models:**

| Model               | Size | GPU Memory | Use Case        |
|---------------------|------|------------|-----------------|
| Mistral-7B-Instruct | 7B   | ~14GB      | General purpose |
| TinyLlama-1.1B      | 1.1B | ~4GB       | Testing, demos  |
| CodeLlama-7B        | 7B   | ~14GB      | Code generation |

### 5. Karpenter for GPU Autoscaling

Karpenter provides just-in-time node provisioning for GPU and training workloads:

**Key Benefits:**
- Faster node provisioning than Cluster Autoscaler
- Native SPOT instance support with fallback to on-demand
- Right-sizing: Provisions optimal instance types automatically
- Consolidation: Removes underutilized nodes to reduce costs

**NodePools Configured:**

| NodePool | Instance Types | Capacity | Taints |
|----------|---------------|----------|--------|
| gpu-workloads | g4dn, g5, p3, p4d | SPOT preferred | `nvidia.com/gpu=true:NoSchedule` |
| training-workloads | c5, m5, r5 (xlarge-4xlarge) | SPOT only | `workload=training:NoSchedule` |

**Example GPU Pod Spec:**
```yaml
spec:
  nodeSelector:
    node-type: gpu
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  resources:
    limits:
      nvidia.com/gpu: "1"
```

### 6. GitOps with ArgoCD

All platform configurations are managed through Git, enabling:
- Version-controlled infrastructure
- Automated sync and drift detection
- Rollback capabilities
- Multi-environment promotion

## Cloud Provider

The platform is deployed on AWS with production-ready Terraform modules:

| Cloud | Module         | Status             | Key Services                            |
|-------|----------------|--------------------|-----------------------------------------|
| AWS   | `modules/eks`  | **Production Ready** | EKS, S3, RDS, ALB, IRSA               |

The Kubernetes layer (KServe, MLflow, ArgoCD) is cloud-agnostic and can be adapted to other providers.

## AWS Infrastructure

### Terraform EKS Module

The platform includes a production-ready Terraform module for AWS EKS:

```
infrastructure/terraform/
├── bootstrap/           # AWS prerequisites (S3, DynamoDB, GitHub OIDC)
├── modules/eks/         # AWS EKS module
│   ├── main.tf          # VPC, EKS cluster, node groups, S3, RDS, IRSA
│   ├── variables.tf     # Configurable inputs
│   └── outputs.tf       # Cluster endpoints, ARNs
└── environments/dev/    # Main deployment configuration
    ├── main.tf          # EKS + Helm releases
    ├── outputs.tf       # Access information
    └── variables.tf     # Environment variables
```

**Node Groups:**
- **General**: Platform services (t3.large, ON_DEMAND)
- **Training**: ML training jobs (c5.2xlarge, SPOT, scale-to-zero)
- **GPU**: GPU workloads (g4dn.xlarge, SPOT, scale-to-zero)

**AWS Resources Created:**
- VPC with public/private subnets across 3 AZs
- EKS cluster with managed node groups
- S3 bucket for MLflow artifacts
- RDS PostgreSQL for MLflow metadata
- IAM roles with IRSA for secure pod authentication
- AWS Load Balancer Controller for ALB Ingress

### Helm Releases (via Terraform)

The dev environment Terraform automatically deploys:

| Component                    | Chart                                    | Purpose             |
|------------------------------|------------------------------------------|---------------------|
| AWS Load Balancer Controller | eks-charts/aws-load-balancer-controller  | ALB Ingress         |
| cert-manager                 | jetstack/cert-manager                    | TLS certificates    |
| ArgoCD                       | argo/argo-cd                             | GitOps deployments  |
| KServe CRDs                  | kserve/kserve-crd                        | Custom resources    |
| KServe Controller            | kserve/kserve                            | Model serving       |
| MLflow                       | community-charts/mlflow                  | Experiment tracking |

### CI/CD Pipeline

GitHub Actions workflows provide automated validation:

```yaml
# .github/workflows/ci.yaml
jobs:
  validate-manifests:    # Kubernetes manifest validation
  lint-python:           # Ruff linter and formatter
  validate-terraform:    # Terraform fmt and validate
  security-scan:         # Trivy and Checkov security scans
  validate-helm:         # Helm values validation
  test-python:           # Pipeline compilation tests
```

## Data Flow

```
┌─────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐    ┌────────┐
│  Data   │───▶│ Feature  │───▶│ Train   │───▶│ Register │───▶│ Serve  │
│ Source  │    │  Store   │    │ Model   │    │  Model   │    │ Model  │
└─────────┘    └──────────┘    └─────────┘    └──────────┘    └────────┘
     │              │               │              │               │
     └──────────────┴───────────────┴──────────────┴───────────────┘
                              │
                    ┌─────────▼────────────┐
                    │     Observability    │
                    │ (Prometheus/Grafana) │
                    └──────────────────────┘
```

## Infrastructure Layers

### Layer 1: AWS Infrastructure
- VPC with public/private subnets
- EKS cluster with managed node groups
- RDS PostgreSQL for MLflow
- S3 for artifact storage
- ALB for external access

### Layer 2: Platform Services
- AWS Load Balancer Controller
- cert-manager for TLS
- Prometheus/Grafana for monitoring
- External-dns for DNS management (optional)

### Layer 3: ML Platform
- Argo Workflows
- MLflow 3.x
- KServe (RawDeployment mode)
- ArgoCD for GitOps

### Layer 4: Applications
- Training pipelines
- Inference services
- Feature stores
- Monitoring dashboards

## Security Architecture

### Network Policies

The platform implements namespace isolation with Kubernetes NetworkPolicies:

```
infrastructure/kubernetes/network-policies.yaml
```

**Policy Summary:**

| Namespace | Ingress From                 | Egress To            |
|-----------|------------------------------|----------------------|
| mlops     | ALB (inference), internal    | -                    |
| mlflow    | mlops, kubeflow, kserve, ALB | PostgreSQL (RDS), S3 |
| kubeflow  | ALB (UI)                     | mlflow, kserve       |
| kserve    | kube-system                  | Kubernetes API       |

### Security Layers

```
┌───────────────────────────────────────────────────────────────┐
│                    Security Layers                            │
├───────────────────────────────────────────────────────────────┤
│  Network Policies      │  Pod Security    │  RBAC             │
│  ─────────────────     │  ─────────────   │  ──────           │
│  - Namespace isolation │  - Non-root      │  - Role per       │
│  - Ingress/Egress      │  - Read-only FS  │    namespace      │
│  - VPC security groups │  - Capabilities  │  - Least          │
│                        │                  │    privilege      │
├───────────────────────────────────────────────────────────────┤
│  IRSA (AWS)            │  Image Security  │  Audit            │
│  ─────────────────     │  ──────────────  │  ─────            │
│  - Pod-level IAM       │  - Signed images │  - CloudTrail     │
│  - No static creds     │  - Vulnerability │  - EKS audit logs │
│  - S3/RDS access       │    scanning      │                   │
└───────────────────────────────────────────────────────────────┘
```

## Observability

### Prometheus Monitoring

The platform includes ServiceMonitors for metrics collection:

```yaml
# infrastructure/kubernetes/monitoring.yaml
- ServiceMonitor: mlflow          # MLflow tracking server
- ServiceMonitor: kserve-inference # Inference services
- PodMonitor: kubeflow-pipelines  # Pipeline runs
```

### Alerting Rules

Pre-configured PrometheusRules for common issues:

| Alert                    | Condition               | Severity |
|--------------------------|-------------------------|----------|
| HighInferenceLatency     | P95 > 1s for 5m         | warning  |
| HighInferenceErrorRate   | >5% errors for 5m       | critical |
| InferenceServiceRestarts | >3 restarts/hour        | warning  |
| MLflowDown               | Server unreachable 2m   | critical |
| HighPipelineFailureRate  | >10% failures/hour      | warning  |
| LowGPUUtilization        | <20% for 30m            | info     |

### Grafana Dashboard

A pre-built dashboard is included as a ConfigMap:
- Inference requests/sec
- P95 latency by model
- Active models count
- Error rate percentage
- Request rate by model

## Scalability Considerations

### Horizontal Scaling
- Argo Workflows: Multiple workflow controllers
- MLflow: Stateless tracking server behind ALB
- KServe: HPA based on inference latency/throughput

### GPU Resource Management
```yaml
# GPU quota per namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-quota
spec:
  hard:
    nvidia.com/gpu: "4"
```

### Cost Optimization
- SPOT instances for training and GPU nodes
- Scale-to-zero for training/GPU node groups
- Single NAT gateway for dev environment
- Resource requests/limits enforcement

## Deployment Workflow

### AWS Deployment

```bash
# Deploy entire platform (~15-20 minutes)
make deploy

# Check status
make status

# Destroy when done
make destroy
```

### Manual Terraform

```bash
# Initialize Terraform
make terraform-init

# Plan infrastructure changes
make terraform-plan

# Apply infrastructure changes
make terraform-apply

# Port forward services
make port-forward-mlflow   # localhost:5000
make port-forward-argocd   # localhost:8080
```

### CI/CD Flow

```
Push to main
    │
    ├── validate-manifests (kubeconform)
    ├── lint-python (ruff)
    ├── validate-terraform (fmt, validate)
    ├── security-scan (trivy, checkov)
    └── test-python (pipeline compilation)
         │
         └── All pass → Ready for deployment
```

## External Access

### ALB Ingress

Services are exposed via AWS Application Load Balancer:

| Service | Ingress Class | Scheme |
|---------|--------------|--------|
| ArgoCD | alb | internet-facing |
| MLflow | alb | internet-facing |

Get ALB URLs after deployment:
```bash
kubectl get ingress -A
```

### Port Forwarding (Development)

For local development or when ALB is not needed:
```bash
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080
```

## Examples

The platform includes working examples to help you get started:

| Example | Description | Complexity |
|---------|-------------|------------|
| [LLM Inference](../examples/llm-inference/) | Mistral-7B, TinyLlama, CodeLlama with vLLM on GPU | Advanced |

## Component Versions

Current versions deployed by the platform:

| Component | Version | Notes |
|-----------|---------|-------|
| MLflow | 1.8.1 | Helm chart with S3/RDS backend |
| KServe | 0.16.0 | CNCF Incubating, RawDeployment mode |
| Argo Workflows | 0.46.1 | ML pipeline execution engine |
| Karpenter | 1.8.0 | GPU autoscaling with SPOT support |
| ArgoCD | 7.9.0 | Chart deploys ArgoCD v2.x |
| AWS ALB Controller | 1.16.0 | Kubernetes Ingress with ALB |
| cert-manager | 1.19.1 | TLS certificate management |
| vLLM | 0.8.0 | High-throughput LLM inference |
| Terraform EKS Module | 20.x | Compatible with AWS provider 5.x |