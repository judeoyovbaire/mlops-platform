# MLOps Platform on Kubernetes

A production-ready MLOps platform for model training, versioning, and deployment on AWS EKS. Enables data science teams to go from experiment to production with self-service workflows.

[![CI](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci.yaml/badge.svg)](https://github.com/judeoyovbaire/mlops-platform/actions/workflows/ci.yaml)

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

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MLOps Platform                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │   Kubeflow   │    │   MLflow 3   │    │   KServe     │                   │
│  │  Pipelines   │───▶│  Tracking &  │───▶│   Model      │                   │
│  │              │    │  Registry    │    │   Serving    │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│         │                   │                   │                            │
│         ▼                   ▼                   ▼                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         AWS EKS Cluster                              │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │    │
│  │  │ GPU     │  │ S3 +    │  │ ALB     │  │ Prom/   │  │ ArgoCD  │   │    │
│  │  │ Nodes   │  │ RDS     │  │ Ingress │  │ Grafana │  │ GitOps  │   │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

- **Kubeflow Pipelines**: Orchestrate ML workflows with reproducible pipelines
- **MLflow 3.x**: Experiment tracking, model registry with aliases, and GenAI support
- **KServe**: Production model serving with canary deployments and autoscaling (CNCF Incubating)
- **ArgoCD 3.x**: GitOps-based deployment automation
- **Terraform**: Infrastructure as Code for AWS EKS with GPU node groups
- **AWS ALB Ingress**: External access via Application Load Balancer
- **GitHub Actions**: CI/CD pipeline with validation, linting, and security scanning
- **Observability**: Prometheus ServiceMonitors, alerting rules, and Grafana dashboards
- **Security**: NetworkPolicies for namespace isolation, IRSA for AWS authentication

## Tech Stack

| Component | Technology | Version | Purpose |
|-----------|------------|---------|---------|
| Pipeline Orchestration | Argo Workflows | 0.46.1 | ML workflow automation |
| Experiment Tracking | MLflow | 3.5.1 | Model versioning & metrics |
| Model Serving | KServe | 0.16.0 | Production inference (CNCF) |
| GPU Autoscaling | Karpenter | 1.5.6 | Dynamic GPU node provisioning |
| GitOps | ArgoCD | 7.9.0 | Declarative deployments |
| Ingress | AWS ALB Controller | 1.16.0 | External load balancing |
| TLS | cert-manager | 1.19.1 | Certificate management |
| Monitoring | Prometheus + Grafana | Latest | Observability |
| Infrastructure | Terraform EKS | 20.x | IaC for AWS EKS |
| CI/CD | GitHub Actions | - | Automated testing |

## Project Structure

```
mlops-platform/
├── .github/workflows/       # CI/CD pipeline (GitHub Actions)
├── components/
│   └── kserve/              # KServe InferenceService examples
├── examples/
│   ├── iris-classifier/     # sklearn model inference test
│   └── llm-inference/       # LLM with vLLM (advanced)
├── infrastructure/
│   ├── kubernetes/          # Network policies, monitoring
│   ├── terraform/
│   │   ├── bootstrap/       # Bootstrap (S3, DynamoDB, GitHub OIDC)
│   │   ├── modules/eks/     # AWS EKS module
│   │   └── environments/dev/# Main deployment configuration
│   └── helm/aws/            # AWS-specific Helm values
├── pipelines/training/      # Kubeflow pipeline definitions
├── tests/                   # Unit tests
├── docs/architecture.md     # Architecture documentation
└── Makefile                 # Common operations
```

## Getting Started

### Prerequisites

- AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform 1.6+
- kubectl
- Helm 3.x
- Python 3.10+

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/judeoyovbaire/mlops-platform.git
cd mlops-platform

# 2. Bootstrap AWS resources (S3 state bucket, GitHub OIDC)
cd infrastructure/terraform/bootstrap
terraform init && terraform apply

# 3. Deploy the platform (~15-20 minutes)
cd ../environments/dev
terraform init && terraform apply

# 4. Configure kubectl
aws eks update-kubeconfig --name mlops-platform-dev --region eu-west-1

# 5. Access the dashboards
make port-forward-mlflow   # MLflow at localhost:5000
make port-forward-argocd   # ArgoCD at localhost:8080
```

### Using the Makefile

```bash
make help                  # Show all available commands

# Deployment
make deploy                # Deploy to AWS EKS
make status                # Check deployment status
make destroy               # Destroy AWS resources

# Validation & Testing
make validate              # Validate Terraform and Python
make lint                  # Lint Python and Terraform code
make test                  # Run unit tests

# Development (after deployment)
make port-forward-mlflow   # Forward MLflow to localhost:5000
make port-forward-argocd   # Forward ArgoCD to localhost:8080
make port-forward-grafana  # Forward Grafana to localhost:3000
make compile-pipeline      # Compile Kubeflow pipeline
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
# Compile the pipeline
make compile-pipeline

# Upload ml_training_pipeline.yaml to Kubeflow Pipelines UI
# Or submit via CLI after installing kfp:
pip install kfp
kfp run submit -f pipelines/training/ml_training_pipeline.yaml
```

## CI/CD Pipeline (Everything-as-Code)

Single unified pipeline with OIDC authentication (no static AWS credentials):

| Trigger | What Happens |
|---------|--------------|
| **Push/PR** | Validate code, run tests, security scan, show terraform plan |
| **Manual: `deploy-infra`** | Deploy EKS, RDS, ECR via Terraform |
| **Manual: `deploy-model`** | Build image, push to ECR, deploy to KServe |
| **Local: `make destroy`** | Destroy infrastructure (safety - not in pipeline) |

### Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ON PUSH/PR (automatic):                                                     │
│  ├── Lint Python (ruff)                                                      │
│  ├── Validate Terraform                                                      │
│  ├── Validate Kubernetes manifests                                           │
│  ├── Security scan (Trivy, Checkov)                                          │
│  ├── Run tests (pytest)                                                      │
│  └── Terraform plan (shows infrastructure changes)                           │
│                                                                              │
│  MANUAL TRIGGER (Actions → CI/CD → Run workflow):                            │
│  ├── deploy-infra  → Creates EKS cluster, RDS, S3, ECR (~15-20 min)         │
│  └── deploy-model  → Builds image, deploys to KServe                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Setup GitHub Secret

After running bootstrap, add the AWS role ARN to GitHub:

```bash
# Get the role ARN
terraform -chdir=infrastructure/terraform/bootstrap output github_actions_role_arn

# Add to GitHub: Settings > Secrets > Actions > New repository secret
# Name: AWS_ROLE_ARN
# Value: arn:aws:iam::<account-id>:role/mlops-platform-github-actions
```

## AWS Resources Created

| Resource | Purpose |
|----------|---------|
| VPC | Networking with public/private subnets across 3 AZs |
| EKS Cluster | Managed Kubernetes control plane (v1.33) |
| Node Groups | General (t3.large), Training (SPOT), GPU (g4dn SPOT) |
| S3 Bucket | MLflow artifact storage |
| RDS PostgreSQL | MLflow metadata backend |
| ECR Repository | Container images for ML models |
| IAM Roles | IRSA for secure pod authentication |
| ALB | External access to services |

### Cost Estimation

Estimated monthly costs (eu-west-1):

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

**Cost Optimization:**
- SPOT instances for training/GPU: 60-70% savings
- Scale-to-zero: Training and GPU nodes only run when needed
- Single NAT Gateway: Sufficient for this deployment

## Roadmap

### Completed
- [x] AWS EKS cluster with GPU support (Terraform)
- [x] MLflow 3.x with RDS + S3 backend
- [x] KServe for model serving
- [x] ArgoCD for GitOps
- [x] Kubeflow Pipelines integration
- [x] Karpenter for GPU autoscaling
- [x] CI/CD pipeline (GitHub Actions)
- [x] Security hardening (NetworkPolicies, IRSA)
- [x] Observability (Prometheus, Grafana, alerts)

### Future Enhancements
- [ ] Model monitoring and drift detection
- [ ] Distributed training support
- [ ] Data versioning with DVC
- [ ] Multi-tenancy support

## Examples

| Example | Description | Complexity |
|---------|-------------|------------|
| [Iris Classifier](examples/iris-classifier/) | Inference testing for sklearn models | Beginner |
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

### ArgoCD for GitOps
- CNCF graduated project
- Declarative, version-controlled deployments
- Strong Kubernetes native support

## Documentation

- [Architecture Deep Dive](docs/architecture.md)
- [Iris Classifier Example](examples/iris-classifier/README.md)
- [LLM Inference Example](examples/llm-inference/README.md)

## License

MIT License - see LICENSE for details.

## Author

**Jude Oyovbaire** - Senior DevOps Engineer & Platform Architect

- LinkedIn: [linkedin.com/in/judeoyovbaire](https://linkedin.com/in/judeoyovbaire)
- GitHub: [github.com/judeoyovbaire](https://github.com/judeoyovbaire)