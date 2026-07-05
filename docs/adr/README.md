# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the MLOps Platform.

## What is an ADR?

An Architecture Decision Record captures an important architectural decision made along with its context and consequences. ADRs help teams understand why certain decisions were made and provide historical context for future maintainers.

## ADR Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-kserve-over-seldon.md) | Use KServe over Seldon Core for Model Serving | Accepted | 2024-01 |
| [002](002-karpenter-over-cluster-autoscaler.md) | Use Karpenter over Cluster Autoscaler | Accepted | 2024-01 |
| [003](003-rawdeployment-mode-kserve.md) | Use RawDeployment Mode for KServe | Accepted | 2024-01 |
| [004](004-multi-cloud-infrastructure-strategy.md) | Multi-Cloud Infrastructure Strategy | Accepted | 2025-01 |
| [005](005-oidc-authentication-over-static-credentials.md) | OIDC Authentication Over Static Credentials | Accepted | 2025-01 |
| [006](006-argo-workflows-over-kubeflow-pipelines.md) | Argo Workflows Over Kubeflow Pipelines | Accepted | 2025-01 |
| [007](007-skip-service-mesh.md) | Skip Service Mesh | Accepted | 2026-02 |
| [008](008-supply-chain-security.md) | Supply Chain Security with Sigstore and SLSA | Accepted | 2026-05 |
| [009](009-progressive-delivery.md) | Argo Rollouts for Progressive Delivery | Accepted | 2026-05 |
| [010](010-terraform-over-opentofu.md) | Terraform Over OpenTofu | Accepted | 2026-05 |
| [011](011-uv-over-pip.md) | uv Over pip for Python Package Management | Accepted | 2026-05 |
| [012](012-terragrunt-evaluation.md) | Evaluate Terragrunt for DRY Terraform Configuration | Superseded by 015 | 2026-05 |
| [013](013-descope-drift-triggered-retraining.md) | Descope Drift-Triggered Retraining | Accepted | 2026-07 |
| [014](014-aws-first-verification.md) | AWS-First Verification Strategy | Accepted | 2026-07 |
| [015](015-shared-aws-platform-module.md) | Shared aws-platform Module for the K8s Platform Layer | Accepted | 2026-07 |

## Creating a New ADR

1. Copy the template:
   ```bash
   cp docs/adr/template.md docs/adr/NNN-title.md
   ```

2. Fill in the sections following the template structure

3. Update the index in this README

4. Submit a PR for review

## ADR Lifecycle

- **Proposed**: Initial state, under discussion
- **Accepted**: Decision has been agreed upon
- **Deprecated**: Decision is no longer relevant
- **Superseded**: Replaced by a newer ADR
