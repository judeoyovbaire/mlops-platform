# ADR-007: Skip Service Mesh

## Status

Accepted

## Context

Service meshes like Istio and Linkerd provide mTLS, observability, and traffic management for microservices. Many KServe deployments use Istio for ingress and traffic splitting. As the MLOps platform scales, we need to decide whether to adopt a service mesh.

Key factors:

- KServe already runs in RawDeployment mode (ADR-003), which avoids the Istio/Knative dependency entirely
- The platform's primary workloads are batch ML training pipelines and model inference endpoints, not high-fanout microservice architectures where service meshes provide the most value
- OpenTelemetry (OTEL) is already integrated for distributed tracing across pipeline steps
- Prometheus and Grafana provide metrics and alerting

## Decision

We will **not** adopt a service mesh at this time. Instead we rely on:

1. **Kubernetes NetworkPolicies** for namespace-level network segmentation
2. **OpenTelemetry** for distributed tracing and observability
3. **Prometheus/Grafana** for metrics collection and dashboarding
4. **NGINX Ingress Controller** for external traffic routing
5. **KServe RawDeployment mode** (ADR-003) for model serving without Knative/Istio

## Consequences

### Positive

- Eliminates significant operational complexity (Istio control plane, sidecar injection, CRD sprawl)
- Reduces resource overhead — no sidecar proxies on every pod consuming CPU/memory
- Faster pod startup times without sidecar injection
- Simpler debugging — no additional network hop through proxy
- Fewer moving parts for multi-cloud deployment

### Negative

- No automatic mTLS between services (acceptable for internal cluster traffic in dev/staging)
- No built-in traffic splitting for canary deployments (can be added via Argo Rollouts if needed)
- No automatic retry/circuit-breaking at the mesh layer

### Neutral

- If mTLS becomes a production requirement, Istio ambient mesh (sidecar-free) can be adopted incrementally
- NetworkPolicies require explicit maintenance but are simpler to reason about

## Alternatives Considered

### Alternative 1: Istio

**Pros:**
- Automatic mTLS between all services
- Rich traffic management (canary, fault injection, retries)
- Deep integration with KServe Serverless mode

**Cons:**
- Heavy resource footprint (control plane + per-pod sidecars)
- Complex operational burden across three clouds
- Not needed since KServe uses RawDeployment mode

**Why not chosen:** The operational complexity outweighs the benefits for the current scale and workload profile. KServe RawDeployment removes the primary motivation for Istio.

### Alternative 2: Linkerd

**Pros:**
- Lighter than Istio, simpler to operate
- Automatic mTLS with minimal configuration
- Rust-based data plane (lower resource usage)

**Cons:**
- Still adds sidecar proxies to every pod
- Less ecosystem integration than Istio
- Additional component to maintain across three clouds

**Why not chosen:** Even a lightweight mesh adds operational overhead that isn't justified by the current workload pattern (batch pipelines + inference endpoints).

## References

- [ADR-003: RawDeployment Mode for KServe](003-rawdeployment-mode-kserve.md)
- [Istio Ambient Mesh](https://istio.io/latest/docs/ambient/)
- [KServe Deployment Modes](https://kserve.github.io/kserve/latest/)
