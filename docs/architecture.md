# Architecture Deep Dive

## Overview

The MLOps Platform is designed to provide a complete ML lifecycle management solution on Kubernetes. It follows cloud-native principles and enables teams to build, train, deploy, and monitor ML models at scale.

## Core Components

### 1. Kubeflow Pipelines

Kubeflow Pipelines orchestrates ML workflows as directed acyclic graphs (DAGs). Each step in a pipeline runs as a container, enabling reproducibility and scalability.

**Key Features:**
- Pipeline versioning and lineage tracking
- Parallel execution of pipeline steps
- Caching for faster iteration
- Integration with MLflow for experiment tracking

```yaml
# Example pipeline structure
pipeline:
  - data-ingestion
  - data-validation
  - feature-engineering
  - model-training (GPU)
  - model-evaluation
  - model-registration
```

### 2. MLflow 3.x

MLflow provides the experiment tracking and model registry capabilities.

**Components:**
- **Tracking Server**: Logs parameters, metrics, and artifacts
- **Model Registry**: Central repository for model versions with aliases
- **Backend Store**: PostgreSQL for metadata
- **Artifact Store**: S3/GCS/MinIO for model artifacts

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
              │ PostgreSQL │           │  S3/MinIO     │
              │ (metadata) │           │  (artifacts)  │
              └───────────┘           └───────────────┘
```

### 3. KServe

KServe (CNCF Incubating) handles model serving with advanced deployment strategies. It replaced Seldon Core due to licensing changes (Seldon moved to BSL 1.1 in Jan 2024).

**Features:**
- Serverless inference with scale-to-zero
- Canary deployments with traffic splitting
- Native support for sklearn, PyTorch, TensorFlow, vLLM
- MLflow model integration
- Autoscaling with Knative or KEDA

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
      storageUri: gs://models/sklearn/iris
```

### 4. GitOps with ArgoCD 3.x

All platform configurations are managed through Git, enabling:
- Version-controlled infrastructure
- Automated sync and drift detection
- Rollback capabilities
- Multi-environment promotion

## Infrastructure

### Terraform EKS Module

The platform includes a production-ready Terraform module for AWS EKS:

```
infrastructure/terraform/
├── modules/eks/
│   ├── main.tf          # VPC, EKS cluster, node groups
│   ├── variables.tf     # Configurable inputs
│   └── outputs.tf       # Cluster endpoints, ARNs
└── environments/dev/
    ├── main.tf          # Dev environment config
    └── terraform.tfvars.example
```

**Node Groups:**
- **General**: Platform services (t3.large, ON_DEMAND)
- **Training**: ML training jobs (c5.2xlarge, SPOT)
- **GPU**: GPU workloads (g4dn.xlarge, SPOT)

**AWS Resources Created:**
- VPC with public/private subnets across 3 AZs
- EKS cluster with managed node groups
- S3 bucket for MLflow artifacts
- RDS PostgreSQL for MLflow metadata
- IAM roles with IRSA for secure pod authentication

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
┌─────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐    ┌─────────┐
│  Data   │───▶│ Feature  │───▶│ Train   │───▶│ Register │───▶│  Serve  │
│ Source  │    │ Store    │    │ Model   │    │ Model    │    │ Model   │
└─────────┘    └──────────┘    └─────────┘    └──────────┘    └─────────┘
     │              │               │              │               │
     └──────────────┴───────────────┴──────────────┴───────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Observability   │
                    │ (Prometheus/Grafana)│
                    └───────────────────┘
```

## Infrastructure Layers

### Layer 1: Kubernetes Cluster
- Managed Kubernetes (EKS/GKE/AKS)
- GPU node pools with NVIDIA drivers
- Cluster autoscaling
- Network policies for isolation

### Layer 2: Platform Services
- Istio service mesh for traffic management
- Prometheus/Grafana for monitoring
- Cert-manager for TLS
- External-dns for DNS management

### Layer 3: ML Platform
- Kubeflow Pipelines
- MLflow 3.x
- KServe
- Jupyter Hub (optional)

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
| Namespace | Ingress From | Egress To |
|-----------|--------------|-----------|
| mlops | istio-system (inference) | - |
| mlflow | mlops, kubeflow, kserve | PostgreSQL, S3 |
| kubeflow | istio-system (UI) | mlflow, kserve |
| kserve | kube-system | Kubernetes API |

### Security Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Security Layers                       │
├─────────────────────────────────────────────────────────┤
│  Network Policies    │  Pod Security    │  RBAC         │
│  ─────────────────   │  ─────────────   │  ──────       │
│  - Namespace isolation│  - Non-root     │  - Role per   │
│  - Ingress/Egress    │  - Read-only FS │    namespace  │
│  - Service mesh mTLS │  - Capabilities │  - Least      │
│                      │                 │    privilege  │
├─────────────────────────────────────────────────────────┤
│  Secrets Management  │  Image Security │  Audit        │
│  ─────────────────   │  ──────────────│  ─────         │
│  - External Secrets  │  - Signed images│  - Audit logs │
│  - Vault integration │  - Vulnerability│  - Compliance │
│  - IRSA (AWS)        │    scanning    │    reports    │
└─────────────────────────────────────────────────────────┘
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

| Alert | Condition | Severity |
|-------|-----------|----------|
| HighInferenceLatency | P95 > 1s for 5m | warning |
| HighInferenceErrorRate | >5% errors for 5m | critical |
| InferenceServiceRestarts | >3 restarts/hour | warning |
| MLflowDown | Server unreachable for 2m | critical |
| HighPipelineFailureRate | >10% failures/hour | warning |
| LowGPUUtilization | <20% for 30m | info |

### Grafana Dashboard

A pre-built dashboard is included as a ConfigMap:
- Inference requests/sec
- P95 latency by model
- Active models count
- Error rate percentage
- Request rate by model

## Scalability Considerations

### Horizontal Scaling
- Kubeflow Pipelines: Multiple workflow controllers
- MLflow: Stateless tracking server behind load balancer
- KServe: HPA/KEDA based on inference latency/throughput, scale-to-zero

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
- Spot/preemptible instances for training jobs
- GPU time-slicing for inference
- Cluster autoscaler with scale-to-zero
- Resource requests/limits enforcement

## Development Workflow

### Local Development

```bash
# Validate all manifests
make validate

# Lint code
make lint

# Compile pipeline
make compile-pipeline

# Port forward services
make port-forward-mlflow
make port-forward-argocd
```

### Deployment

```bash
# Install platform
make install

# Deploy example model
make deploy-example

# Check status
make status
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