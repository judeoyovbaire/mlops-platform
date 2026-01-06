# MLOps Platform on Kubernetes

A production-ready, multi-cloud MLOps platform for model training, versioning, and deployment on **AWS EKS** or **Azure AKS**. Enables data science teams to go from experiment to production with self-service workflows.

[![CI/CD](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci-cd.yaml/badge.svg)](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci-cd.yaml)

## The Problem

ML teams often spend more time on infrastructure than on actual machine learning:

| Challenge | Traditional Approach | Time Cost |
|-----------|---------------------|-----------|
| Model deployment | Manual kubectl, Docker builds, config management | 2-3 days per model |
| Environment consistency | "Works on my machine" debugging | Hours of troubleshooting |
| Experiment tracking | Spreadsheets, local files, tribal knowledge | Lost experiments, no reproducibility |
| GPU resource management | Static allocation, idle resources | 60-70% underutilization |
| Production rollbacks | Manual intervention, downtime risk | 30+ minutes MTTR |

## The Solution

This platform provides self-service ML infrastructure where data scientists deploy models without DevOps tickets:

```
Data Scientist                    Platform (Automated)
     │                                    │
     ├── git push model code ────────────►├── CI validates & builds container
     │                                    ├── MLflow registers model version
     │                                    ├── KServe deploys with canary (10%)
     │                                    ├── Prometheus monitors latency/errors
     │                                    └── Auto-rollback if metrics degrade
     │                                    │
     └── Monitor in Grafana ◄─────────────┘
```

## Key Outcomes

| Metric | Before | After | Impact |
|--------|--------|-------|--------|
| Model deployment time | 2-3 days | 15 minutes | **95% faster** |
| Infrastructure setup per project | 40+ hours | 2 hours | **Self-service enablement** |
| GPU utilization | ~30% (static) | 70-85% (autoscaled) | **60% cost reduction on GPU** |
| Failed deployment recovery | 30+ min manual | <2 min auto-rollback | **Reduced MTTR** |
| Experiment reproducibility | Ad-hoc | 100% tracked | **Full audit trail** |

## Multi-Cloud Architecture

Deploy to **AWS** or **Azure** - same MLOps capabilities, cloud-native implementations:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         MLOps Platform                                    │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                 │
│  │     Argo     │    │   MLflow     │    │   KServe     │                 │
│  │  Workflows   │───▶│  Tracking &  │───▶│   Model      │                 │
│  │              │    │  Registry    │    │   Serving    │                 │
│  └──────────────┘    └──────────────┘    └──────────────┘                 │
│         │                   │                   │                         │
│         ▼                   ▼                   ▼                         │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │                    Kubernetes (EKS / AKS)                          │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │   │
│  │  │ GPU     │  │ Storage │  │ Ingress │  │ Prom/   │  │ ArgoCD  │   │   │
│  │  │ Nodes   │  │ Backend │  │         │  │ Grafana │  │ GitOps  │   │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘

AWS EKS                              │  Azure AKS
─────────────────────────────────────│──────────────────────────────────────
• Karpenter (GPU autoscaling)        │  • KEDA (event-driven autoscaling)
• S3 + RDS PostgreSQL                │  • Blob Storage + PostgreSQL Flexible
• ALB Ingress Controller             │  • NGINX Ingress Controller
• IRSA (pod identity)                │  • Workload Identity
• SSM Parameter Store                │  • Azure Key Vault
```

## Features

| Feature | AWS | Azure |
|---------|-----|-------|
| **Pipeline Orchestration** | Argo Workflows | Argo Workflows |
| **Experiment Tracking** | MLflow + S3 + RDS | MLflow + Blob + PostgreSQL |
| **Model Serving** | KServe (RawDeployment) | KServe (RawDeployment) |
| **GitOps** | ArgoCD | ArgoCD |
| **GPU Autoscaling** | Karpenter | KEDA + Cluster Autoscaler |
| **Ingress** | AWS ALB Controller | NGINX Ingress |
| **Pod Identity** | IRSA | Workload Identity |
| **Secrets** | External Secrets + SSM | External Secrets + Key Vault |
| **Security** | PSA, Kyverno, Tetragon | PSA, Kyverno, Tetragon |
| **Monitoring** | Prometheus + Grafana | Prometheus + Grafana |

## Tech Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Pipeline Orchestration | Argo Workflows | 0.46.1 | ML workflow automation |
| Experiment Tracking | MLflow | 3.x | Model versioning & metrics |
| Model Serving | KServe | 0.16.0 | Production inference (CNCF) |
| GPU Autoscaling (AWS) | Karpenter | 1.8.0 | Dynamic GPU node provisioning |
| Event Autoscaling (Azure) | KEDA | 2.18.3 | Event-driven pod scaling |
| GitOps | ArgoCD | 7.9.0 | Declarative deployments |
| Ingress (AWS) | AWS ALB Controller | 1.16.0 | External load balancing |
| Ingress (Azure) | NGINX Ingress | 4.14.1 | External load balancing |
| TLS | cert-manager | 1.19.1 | Certificate management |
| Monitoring | Prometheus + Grafana | 72.6.2 | Observability |
| Infrastructure | Terraform | 1.6+ | IaC for EKS/AKS |
| CI/CD | GitHub Actions | - | Automated testing |

## Project Structure

```
mlops-platform/
├── .github/workflows/          # CI/CD pipeline (multi-cloud)
├── components/
│   └── kserve/                 # KServe InferenceService examples
├── examples/
│   └── llm-inference/          # LLM with vLLM (advanced)
├── infrastructure/
│   ├── kubernetes/             # Network policies, monitoring
│   ├── terraform/
│   │   ├── bootstrap/
│   │   │   ├── aws/            # AWS prerequisites (S3, GitHub OIDC)
│   │   │   └── azure/          # Azure prerequisites (Storage, GitHub OIDC)
│   │   ├── modules/
│   │   │   ├── eks/            # AWS EKS module
│   │   │   └── aks/            # Azure AKS module
│   │   └── environments/
│   │       ├── aws/dev/        # AWS deployment configuration
│   │       └── azure/dev/      # Azure deployment configuration
│   └── helm/
│       ├── aws/                # AWS-specific Helm values
│       └── azure/              # Azure-specific Helm values
├── pipelines/training/         # Argo Workflow pipeline definitions
├── scripts/
│   ├── deploy-aws.sh           # AWS deployment script
│   ├── deploy-azure.sh         # Azure deployment script
│   ├── destroy-aws.sh          # AWS cleanup script
│   └── destroy-azure.sh        # Azure cleanup script
├── tests/                      # Unit tests
├── docs/architecture.md        # Architecture documentation
└── Makefile                    # Common operations
```

## Getting Started

### Prerequisites

**For AWS:**
- AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)

**For Azure:**
- Azure subscription
- Azure CLI configured (`az login`)

**Common:**
- Terraform 1.6+
- kubectl
- Helm 3.x
- Python 3.10+

### Quick Start - AWS

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Bootstrap AWS resources (S3 state bucket, GitHub OIDC)
cd infrastructure/terraform/bootstrap/aws
terraform init && terraform apply

# 3. Deploy the platform (~15-20 minutes)
make deploy-aws

# 4. Access the dashboards
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080
```

### Quick Start - Azure

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Bootstrap Azure resources (Storage Account, GitHub OIDC)
cd infrastructure/terraform/bootstrap/azure
terraform init && terraform apply

# 3. Deploy the platform (~15-25 minutes)
make deploy-azure

# 4. Access the dashboards
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080
```

### Using the Makefile

```bash
make help                  # Show all available commands

# AWS Deployment
make deploy-aws            # Deploy to AWS EKS
make status-aws            # Check AWS deployment status
make secrets-aws           # Retrieve secrets from AWS SSM
make destroy-aws           # Destroy AWS resources

# Azure Deployment
make deploy-azure          # Deploy to Azure AKS
make status-azure          # Check Azure deployment status
make secrets-azure         # Retrieve secrets from Azure Key Vault
make destroy-azure         # Destroy Azure resources

# Validation & Testing
make validate              # Validate Terraform and Python
make lint                  # Lint Python and Terraform code
make test                  # Run unit tests

# Development (after deployment - works with either cloud)
make port-forward-mlflow   # Forward MLflow to localhost:5000
make port-forward-argocd   # Forward ArgoCD to localhost:8080
make port-forward-grafana  # Forward Grafana to localhost:3000
make deploy-example        # Deploy example inference service
```

### Deploy a Model with KServe

```bash
# Deploy example inference services
kubectl apply -f components/kserve/inferenceservice-examples.yaml

# Check status
kubectl get inferenceservice -n mlops

# Test inference
curl -X POST "http://<SERVICE_URL>/v1/models/sklearn-iris:predict" \
  -H "Content-Type: application/json" \
  -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
```

### Run a Training Pipeline

```bash
# Apply the workflow template
kubectl apply -f pipelines/training/ml-training-workflow.yaml

# Run the training pipeline
kubectl create -f pipelines/training/ml-training-workflow.yaml -n argo

# Check workflow status
kubectl get workflows -n argo

# View logs
argo logs -n argo <workflow-name>
```

## CI/CD Pipeline

Single unified pipeline with OIDC authentication for both clouds (no static credentials):

| Trigger | What Happens |
|---------|--------------|
| **Push/PR** | Validate code, run tests, security scan, show terraform plan for both clouds |
| **Manual: `aws` + `deploy-infra`** | Deploy AWS EKS infrastructure via Terraform |
| **Manual: `azure` + `deploy-infra`** | Deploy Azure AKS infrastructure via Terraform |
| **Manual: `deploy-model`** | Deploy example InferenceServices to KServe |
| **Local: `make destroy-*`** | Destroy infrastructure (safety - not in pipeline) |

### Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ON PUSH/PR (automatic):                                                    │
│  ├── Lint Python (ruff)                                                     │
│  ├── Validate Terraform (AWS + Azure)                                       │
│  ├── Validate Kubernetes manifests                                          │
│  ├── Security scan (Trivy)                                                  │
│  ├── Run tests (pytest)                                                     │
│  └── Terraform plan (parallel: AWS and Azure)                               │
│                                                                             │
│  MANUAL TRIGGER (Actions → CI/CD → Run workflow):                           │
│  ├── Cloud: aws/azure                                                       │
│  ├── deploy-infra  → Creates EKS/AKS cluster (~15-25 min)                   │
│  └── deploy-model  → Deploys example InferenceServices                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Setup GitHub Secrets

**For AWS:**
```bash
terraform -chdir=infrastructure/terraform/bootstrap/aws output github_actions_role_arn
# Add to GitHub: Settings > Secrets > AWS_ROLE_ARN
```

**For Azure:**
```bash
terraform -chdir=infrastructure/terraform/bootstrap/azure output -json
# Add to GitHub: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
```

## Cloud Resources

### AWS Resources

| Resource | Purpose |
|----------|---------|
| VPC | Networking with public/private subnets across 3 AZs |
| EKS Cluster | Managed Kubernetes control plane (v1.34) |
| Node Groups | General (t3.large), Training (SPOT), GPU (g4dn SPOT) |
| S3 Bucket | MLflow artifact storage |
| RDS PostgreSQL | MLflow metadata backend |
| ECR Repository | Container images for ML models |
| IAM Roles | IRSA for secure pod authentication |
| ALB | External access to services |

### Azure Resources

| Resource | Purpose |
|----------|---------|
| Virtual Network | Networking with AKS and PostgreSQL subnets |
| AKS Cluster | Managed Kubernetes (v1.34) |
| Node Pools | System, Training (Spot), GPU (Spot) |
| Storage Account | MLflow artifact storage (Blob) |
| PostgreSQL Flexible Server | MLflow metadata backend |
| Container Registry | Container images for ML models |
| Managed Identities | Workload Identity for pod authentication |
| Key Vault | Secrets management |

### Cost Estimation

**AWS (eu-west-1):**

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| EKS Cluster | Control plane | $73 |
| General Nodes | 2x t3.large (ON_DEMAND) | ~$120 |
| Training Nodes | c5.2xlarge (SPOT, scale-to-zero) | ~$30-50 |
| GPU Nodes | g4dn.xlarge (SPOT, scale-to-zero) | ~$50-100 |
| NAT Gateway | Single (cost optimization) | ~$45 |
| RDS PostgreSQL | db.t3.small | ~$25 |
| S3 + ALB | Minimal usage | ~$10-20 |
| **Total** | | **~$350-450/month** |

**Azure (westeurope):**

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| AKS Control Plane | Free tier | $0 |
| System Nodes | 2x Standard_D4s_v3 | ~$280 |
| Training Nodes | Standard_D8s_v3 (Spot, scale-to-zero) | ~$30-50 |
| GPU Nodes | Standard_NC6s_v3 (Spot, scale-to-zero) | ~$50-100 |
| PostgreSQL | B_Standard_B1ms | ~$15 |
| Storage Account | Standard LRS | ~$5 |
| Key Vault + Load Balancer | Standard | ~$23 |
| **Total** | | **~$400-470/month** |

**Cost Optimization:**
- SPOT instances for training/GPU: 60-70% savings
- Scale-to-zero: Training and GPU nodes only run when needed
- Single NAT Gateway (AWS) / Standard LB (Azure)

## Roadmap

### Completed
- [x] AWS EKS cluster with GPU support (Terraform)
- [x] Azure AKS cluster with GPU support (Terraform)
- [x] MLflow 3.x with cloud-native storage backends
- [x] KServe for model serving
- [x] ArgoCD for GitOps
- [x] Argo Workflows for ML pipelines
- [x] Karpenter for GPU autoscaling (AWS)
- [x] KEDA for event-driven autoscaling (Azure)
- [x] CI/CD pipeline with multi-cloud support
- [x] Security hardening (PSA, Kyverno policies, Tetragon runtime security)
- [x] Observability (Prometheus, Grafana, alerts)
- [x] External Secrets integration (SSM / Key Vault)

### Future Enhancements
- [ ] GCP GKE support
- [ ] Distributed training support
- [ ] Data versioning with DVC
- [ ] Production environment configuration

## Examples

| Example | Description | Complexity |
|---------|-------------|------------|
| [LLM Inference](examples/llm-inference/) | Mistral-7B with vLLM on GPU | Advanced |

## Why These Tools?

### MLflow 3.x over alternatives
- Open source, framework-agnostic
- Native GenAI/LLM support (prompt versioning, agent tracing)
- Model aliases replace deprecated staging workflow
- Largest community adoption

### KServe over Seldon Core
- **Licensing**: Seldon Core moved to BSL 1.1 (paid for commercial use as of Jan 2024)
- KServe is fully open source (Apache 2.0), CNCF Incubating project
- Better PyTorch support out-of-the-box
- Serverless inference with scale-to-zero

### Multi-Cloud Architecture
- Same MLOps capabilities on AWS or Azure
- Cloud-native implementations (IRSA vs Workload Identity, Karpenter vs KEDA)
- Demonstrates enterprise-grade infrastructure patterns
- Flexibility to deploy where your data resides

## Documentation

- [Architecture Deep Dive](docs/architecture.md)
- [LLM Inference Example](examples/llm-inference/README.md)

## License

MIT License - see LICENSE for details.

## Author

**Jude Oyovbaire** - Senior Platform & DevOps Engineer

- Website: [judaire.io](https://judaire.io)
- LinkedIn: [linkedin.com/in/judeoyovbaire](https://linkedin.com/in/judeoyovbaire)
- GitHub: [github.com/judeoyovbaire](https://github.com/judeoyovbaire)
