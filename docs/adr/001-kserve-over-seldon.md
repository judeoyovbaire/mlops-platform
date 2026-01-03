# ADR-001: Use KServe over Seldon Core for Model Serving

## Status

Accepted

## Context

We need a model serving solution for deploying ML models on Kubernetes. The platform should support:
- Multiple ML frameworks (scikit-learn, PyTorch, TensorFlow)
- Autoscaling based on inference load
- Canary deployments and traffic splitting
- LLM serving capabilities
- Integration with MLflow model registry

The two leading options in the Kubernetes ecosystem are:
1. **KServe** (CNCF Incubating project, formerly KFServing)
2. **Seldon Core** (Commercial with open-source version)

## Decision

We will use **KServe v0.16.0** as our model serving solution.

## Consequences

### Positive

- **CNCF Backing**: KServe is a CNCF Incubating project with strong community support and governance
- **Native vLLM Support**: First-class support for vLLM, enabling high-throughput LLM serving
- **Simpler CRD Model**: InferenceService CRD is intuitive and well-documented
- **Scale-to-Zero**: Native support reduces costs when models aren't actively serving
- **Active Development**: Regular releases with new features (v0.16 released Dec 2024)
- **MLflow Integration**: Direct integration with MLflow model registry
- **RawDeployment Mode**: Can run without Knative, reducing operational complexity

### Negative

- **Knative Dependency** (optional): Full features require Knative Serving, though RawDeployment mode avoids this
- **Less Mature Explainability**: Seldon has more mature explainability features
- **Smaller Enterprise Ecosystem**: Seldon has more enterprise integrations out of the box

### Neutral

- Both solutions support the same core ML frameworks
- Migration between them would require rewriting InferenceService manifests
- Monitoring integration is similar for both

## Alternatives Considered

### Alternative 1: Seldon Core

**Pros:**
- Mature enterprise features (explainability, outlier detection)
- Strong A/B testing capabilities
- Commercial support available
- Pre-built operators for many frameworks

**Cons:**
- More complex architecture with multiple components
- Commercial licensing for advanced features
- Less active open-source development recently
- No native vLLM support

**Why not chosen:** KServe's CNCF governance, native vLLM support, and simpler operational model better align with our open-source, cloud-native approach.

### Alternative 2: TensorFlow Serving / TorchServe directly

**Pros:**
- Native performance for specific frameworks
- No abstraction overhead

**Cons:**
- Framework-specific, requires multiple solutions
- No unified API for different model types
- Manual scaling and deployment management

**Why not chosen:** We need a unified solution that supports multiple frameworks with consistent APIs and autoscaling.

## References

- [KServe Documentation](https://kserve.github.io/website/)
- [KServe vs Seldon Comparison](https://www.kubeflow.org/docs/external-add-ons/serving/overview/)
- [CNCF KServe Project](https://www.cncf.io/projects/kserve/)
