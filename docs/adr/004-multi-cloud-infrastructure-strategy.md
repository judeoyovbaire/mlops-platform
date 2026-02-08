# ADR-004: Multi-Cloud Infrastructure Strategy

## Status

Accepted

## Context

The MLOps platform needs to support deployment across multiple cloud providers to:
- Demonstrate cloud-agnostic architecture for portfolio purposes
- Avoid vendor lock-in for production workloads
- Leverage best-of-breed services from each provider (e.g., Karpenter on AWS, KEDA on Azure)

We need a strategy for managing infrastructure code, Helm values, and Kubernetes manifests across AWS EKS, Azure AKS, and GCP GKE.

## Decision

We will use a **shared-module architecture** with cloud-specific environment configurations:

1. **Terraform modules per cloud**: Each cloud provider has its own module (`modules/eks/`, `modules/aks/`, `modules/gke/`) that creates the full infrastructure stack (VPC/VNet, cluster, node pools, storage, registry, secrets).
2. **Common Helm values**: Shared Helm configuration in `infrastructure/helm/common/` with cloud-specific overrides in `infrastructure/helm/{aws,azure,gcp}/`.
3. **Unified Kubernetes manifests**: Cloud-agnostic Kubernetes resources (NetworkPolicies, ResourceQuotas, Kyverno policies) in `infrastructure/kubernetes/`.
4. **OIDC authentication**: All cloud providers use OIDC federation for CI/CD - no static credentials stored in GitHub Secrets.

## Consequences

### Positive

- **Consistent patterns**: All clouds follow the same module structure (VPC, cluster, node pools, storage, registry)
- **Independent deployment**: Each cloud can be deployed independently without affecting others
- **Best practices per cloud**: Each module uses cloud-native best practices (IRSA on AWS, Workload Identity on Azure/GCP)
- **Parallel CI/CD**: Terraform plan runs in parallel across all three clouds

### Negative

- **Higher maintenance**: Three sets of Terraform modules to maintain and keep in sync
- **Feature parity challenges**: Not all clouds support identical features (e.g., Karpenter is AWS-only)
- **Testing complexity**: Need to validate changes across all three providers

### Neutral

- Common MLOps stack (Argo Workflows, MLflow, KServe, Prometheus) is identical across clouds
- Helm values differ primarily in storage backends and ingress configuration

## Alternatives Considered

### Alternative 1: Single Cloud (AWS only)

**Why not chosen:** Limits portfolio demonstration value and creates vendor lock-in.

### Alternative 2: Crossplane or Pulumi for multi-cloud abstraction

**Why not chosen:** Adds abstraction complexity without clear benefit for the three supported clouds. Terraform's HCL is more widely used in the industry.

## References

- [Terraform Multi-Cloud Best Practices](https://developer.hashicorp.com/terraform/tutorials/enterprise/multi-cloud-overview)
- [CNCF Cloud Native Landscape](https://landscape.cncf.io/)
