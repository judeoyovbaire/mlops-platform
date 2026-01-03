# ADR-003: Use RawDeployment Mode for KServe

## Status

Accepted

## Context

KServe supports two deployment modes:
1. **Serverless Mode** (default): Requires Knative Serving for scale-to-zero and request-based autoscaling
2. **RawDeployment Mode**: Uses standard Kubernetes Deployments with HPA for autoscaling

We need to decide which mode to use for our MLOps platform, considering:
- Operational complexity
- Scale-to-zero requirements
- Component dependencies
- Debugging and troubleshooting ease

## Decision

We will use **RawDeployment mode** for KServe, avoiding the Knative dependency.

## Consequences

### Positive

- **Reduced Complexity**: No Knative Serving, Knative Eventing, or Istio dependencies
- **Familiar Primitives**: Uses standard Kubernetes Deployments and Services
- **Easier Debugging**: Standard kubectl commands work without Knative abstractions
- **Lower Resource Overhead**: No Knative controller pods consuming cluster resources
- **Simpler Networking**: No need for Knative's complex networking layer
- **HPA Compatibility**: Works with standard Kubernetes HPA and KEDA
- **Faster Setup**: Significantly reduces initial deployment time

### Negative

- **No Native Scale-to-Zero**: Must use KEDA or custom solutions for scale-to-zero
- **Manual Autoscaling Configuration**: HPA must be configured separately
- **No Request Queuing**: Knative's queue-proxy provides request queuing during scale-up

### Neutral

- Model inference performance is identical in both modes
- Canary deployments work in both modes (traffic splitting)
- Model loading and serving behavior unchanged

## Alternatives Considered

### Alternative 1: Serverless Mode with Knative

**Pros:**
- Native scale-to-zero
- Request-based autoscaling
- Built-in request queuing

**Cons:**
- Requires Knative Serving (~6 additional pods)
- Often requires Istio service mesh
- Complex networking layer
- Debugging requires Knative knowledge
- Additional CRDs and controllers

**Why not chosen:** The operational complexity of maintaining Knative outweighs the benefits. Scale-to-zero can be achieved with Karpenter (node-level) and KEDA (pod-level).

### Alternative 2: Full Knative + Istio Stack

**Pros:**
- Complete serverless experience
- Advanced traffic management
- mTLS out of the box

**Cons:**
- Very high complexity
- Istio adds significant resource overhead
- Steep learning curve
- Over-engineered for our use case

**Why not chosen:** Istio is overkill for internal ML model serving. We use Kubernetes NetworkPolicies for security instead.

## Implementation Details

```yaml
# Enable RawDeployment mode in KServe config
apiVersion: v1
kind: ConfigMap
metadata:
  name: inferenceservice-config
  namespace: kserve
data:
  deploy: |-
    {
      "defaultDeploymentMode": "RawDeployment"
    }
```

Scale-to-zero is achieved through:
1. **Karpenter**: Nodes scale to zero when no pods are scheduled
2. **KEDA (optional)**: Pod-level scaling based on custom metrics

## References

- [KServe RawDeployment Mode](https://kserve.github.io/website/latest/admin/serverless/serverless/#rawdeployment-mode)
- [KServe without Knative](https://github.com/kserve/kserve/blob/master/docs/DEVELOPER_GUIDE.md#deploy-kserve-without-knative)
