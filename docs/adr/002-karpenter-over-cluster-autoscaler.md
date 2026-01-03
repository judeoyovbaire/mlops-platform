# ADR-002: Use Karpenter over Cluster Autoscaler

## Status

Accepted

## Context

We need an autoscaling solution for our EKS cluster that can:
- Provision GPU nodes on-demand for ML training and inference
- Support SPOT instances for cost optimization
- Scale to zero when workloads complete
- Provision nodes quickly (< 2 minutes)
- Handle heterogeneous instance types (CPU, GPU, memory-optimized)

The two main options for EKS autoscaling are:
1. **Karpenter** (AWS open-source project, now CNCF Sandbox)
2. **Cluster Autoscaler** (Kubernetes SIG project)

## Decision

We will use **Karpenter v1.8.0** for node autoscaling.

## Consequences

### Positive

- **Faster Provisioning**: Nodes provision in ~60 seconds vs 3-5 minutes with Cluster Autoscaler
- **Groupless Architecture**: No need to pre-define node groups; Karpenter provisions optimal instances directly
- **Better SPOT Handling**: Native SPOT instance support with automatic fallback to on-demand
- **Consolidation**: Automatically consolidates workloads to reduce node count and cost
- **GPU Awareness**: Better GPU instance selection based on actual workload requirements
- **Just-in-Time Scaling**: Provisions nodes based on pending pod requirements, not pre-defined groups
- **Cost Optimization**: 30-40% cost savings through better bin-packing and SPOT usage
- **CNCF Sandbox**: Growing community adoption and governance

### Negative

- **AWS-Specific**: Karpenter is AWS-native; would need different solution for multi-cloud
- **Learning Curve**: Different mental model than traditional node groups
- **Newer Project**: Less battle-tested than Cluster Autoscaler (though rapidly maturing)
- **IAM Complexity**: Requires additional IAM roles for instance profile management

### Neutral

- Both integrate with EKS managed node groups (we keep static general nodes)
- Monitoring and alerting setup is similar
- Both support taints and tolerations for workload isolation

## Alternatives Considered

### Alternative 1: Cluster Autoscaler

**Pros:**
- Kubernetes-native, works across cloud providers
- Well-documented and mature
- Simpler IAM requirements
- Familiar to most Kubernetes operators

**Cons:**
- Slower node provisioning (3-5 minutes)
- Requires pre-defined node groups
- Less flexible instance type selection
- Poor SPOT instance support
- No consolidation feature

**Why not chosen:** The 3-5 minute provisioning time is unacceptable for ML workloads that need quick scale-up. GPU nodes sitting idle waiting for slow scale-down also increases costs.

### Alternative 2: Manual Node Management

**Pros:**
- Full control over instance lifecycle
- No additional tooling

**Cons:**
- Operational burden
- No automatic scaling
- Cannot handle bursty ML workloads

**Why not chosen:** Completely impractical for dynamic ML training and inference workloads.

## Implementation Details

```yaml
# NodePool configuration for GPU workloads
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-workloads
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["g"]  # GPU instances
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]  # SPOT preferred
      expireAfter: 4h  # Prevent runaway costs
  limits:
    cpu: 100
    memory: 400Gi
```

## References

- [Karpenter Documentation](https://karpenter.sh/)
- [Karpenter vs Cluster Autoscaler](https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/)
- [Karpenter Best Practices](https://aws.github.io/aws-eks-best-practices/karpenter/)
