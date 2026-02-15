# Documentation

Comprehensive documentation for the MLOps Platform.

## Quick Links

| Document | Description |
|----------|-------------|
| [Quick Start](../QUICKSTART.md) | Deploy your first model in 5 minutes |
| [Architecture](architecture.md) | System design and component details |
| [Secrets Management](secrets-management.md) | Credential rotation and security |
| [Performance Tuning](performance-tuning.md) | Optimize inference, training, and infrastructure |
| [Disaster Recovery](disaster-recovery.md) | Backup and recovery procedures |
| [API Reference](api-reference.md) | MLflow and KServe API documentation |
| [Upgrade Procedures](upgrade-procedures.md) | Component upgrade guides |
| [Troubleshooting](troubleshooting.md) | Common issues and solutions |

## Runbooks

Operational guides for day-to-day platform management:

| Runbook | Description |
|---------|-------------|
| [Operations](runbooks/operations.md) | Daily operations, deployments, scaling |
| [Troubleshooting](runbooks/troubleshooting.md) | Common issues and solutions |

## Component Documentation

### ML Platform

- **MLflow 3.x** - Experiment tracking and model registry
- **KServe** - Model serving with canary deployments
- **Argo Workflows** - ML pipeline orchestration

### Infrastructure

- **Terraform Modules** - EKS, AKS, GKE configurations
- **Helm Values** - Cloud-specific component configurations

### Security

- **Pod Security Admission** - Namespace-level security enforcement
- **Kyverno** - Policy-as-code validation
- **Tetragon** - Runtime security monitoring

## Examples

| Example | Description | Location |
|---------|-------------|----------|
| KServe Basic | sklearn model with production config | [examples/kserve/](../examples/kserve/) |
| Canary Deployment | Progressive rollout with traffic splitting | [examples/canary-deployment/](../examples/canary-deployment/) |
| LLM Inference | Mistral-7B with vLLM on GPU | [examples/llm-inference/](../examples/llm-inference/) |
| Drift Detection | Model monitoring with Evidently | [examples/drift-detection/](../examples/drift-detection/) |
| Distributed Training | PyTorch DDP with Kubeflow | [examples/distributed-training/](../examples/distributed-training/) |
| Chaos Testing | Resilience testing with Chaos Mesh | [examples/chaos-testing/](../examples/chaos-testing/) |

## Architecture Diagrams

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MLOps Platform                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│   │    Argo     │    │   MLflow    │    │   KServe    │    │   ArgoCD    │  │
│   │  Workflows  │───▶│  Tracking   │───▶│   Serving   │    │   GitOps    │  │
│   └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│         │                  │                  │                  │          │
│         ▼                  ▼                  ▼                  ▼          │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Kubernetes (EKS / AKS / GKE)                     │   │
│   │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────────────┐ │   │
│   │  │ Prometheus│  │  Kyverno  │  │  Tetragon │  │ External Secrets  │ │   │
│   │  │ + Grafana │  │  Policies │  │  Security │  │    Operator       │ │   │
│   │  └───────────┘  └───────────┘  └───────────┘  └───────────────────┘ │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                      Cloud Provider Layer                           │   │
│   │  AWS: S3 + RDS + ALB + IRSA + Karpenter                             │   │
│   │  Azure: Blob + PostgreSQL + NGINX + Workload Identity + KEDA        │   │
│   │  GCP: GCS + Cloud SQL + NGINX + Workload Identity + NAP             │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│   Data   │────▶│  Train   │────▶│ Register │────▶│  Deploy  │────▶│  Serve   │
│  Source  │     │  Model   │     │  Model   │     │  Canary  │     │ Requests │
└──────────┘     └──────────┘     └──────────┘     └──────────┘     └──────────┘
                      │                │                │                │
                      ▼                ▼                ▼                ▼
                 ┌─────────────────────────────────────────────────────────┐
                 │                    Observability                        │
                 │  MLflow Experiments │ Prometheus Metrics │ Grafana      │
                 └─────────────────────────────────────────────────────────┘
```

### Security Layers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Security Architecture                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Layer 1: Admission Control                                                 │
│  ├── Pod Security Admission (PSA) - Namespace-level enforcement             │
│  └── Kyverno Policies - Resource validation and mutation                    │
│                                                                             │
│  Layer 2: Runtime Security                                                  │
│  ├── Tetragon - eBPF-based process and file monitoring                      │
│  └── Network Policies - Namespace isolation                                 │
│                                                                             │
│  Layer 3: Identity & Access                                                 │
│  ├── IRSA / Workload Identity - No static credentials                       │
│  └── External Secrets - Secure secret injection                             │
│                                                                             │
│  Layer 4: Data Protection                                                   │
│  ├── Encryption at rest (RDS, S3, Cloud SQL, GCS)                           │
│  └── TLS for all service communication                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Contributing

When adding new documentation:

1. Use Markdown format
2. Include code examples where applicable
3. Add diagrams for complex concepts (Mermaid preferred)
4. Update this index with links to new documents
5. Keep troubleshooting guides up to date