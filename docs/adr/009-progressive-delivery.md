# ADR-009: Argo Rollouts for Progressive Delivery

## Status

Accepted

## Context

Deploying ML model updates to production carries risk — a model retrained on drifted data or with degraded accuracy could silently serve bad predictions. The platform needs a progressive delivery mechanism that:

- Gradually shifts traffic to new model versions
- Automatically validates canary health against Prometheus metrics
- Rolls back immediately if quality metrics degrade
- Integrates with the existing Argo ecosystem (Workflows, Events)

## Decision

We will adopt **Argo Rollouts** for progressive delivery of ML model serving workloads.

Canary strategy:
1. 10% traffic → pause 2 min → analysis
2. 25% traffic → pause 2 min → analysis
3. 50% traffic → pause 3 min → analysis
4. 100% traffic (full promotion)

AnalysisTemplates validate:
- **Success rate** >= 95% (from Prometheus)
- **P95 latency** <= 500ms
- **Error rate** < 5%

Auto-rollback triggers on any metric failure.

## Consequences

### Positive

- Automated canary analysis eliminates manual verification of model deployments
- Prometheus-backed metrics provide objective quality gates
- Tight integration with Argo Workflows (training) and Argo Events (triggers) — unified Argo ecosystem
- Dashboard provides real-time visibility into rollout progress
- Rollback is automatic and fast (< 30s)

### Negative

- Additional controller to maintain (argo-rollouts)
- Requires Rollout CRD instead of native Deployment — changes deployment patterns
- AnalysisTemplates need tuning per model type

### Neutral

- Can coexist with KServe InferenceServices (Rollout manages the underlying Deployment)
- Argo Rollouts dashboard provides independent UI from ArgoCD

## Alternatives Considered

### Alternative 1: Flagger

**Pros:**
- Supports multiple mesh/ingress integrations
- Webhook-based analysis extensible

**Cons:**
- Separate ecosystem from Argo Workflows/Events
- Less native Prometheus integration than Argo Rollouts AnalysisTemplates
- Different CRD patterns from rest of platform

**Why not chosen:** Argo Rollouts integrates naturally with the existing Argo ecosystem (Workflows for training, Events for triggers), reducing operational complexity.

### Alternative 2: KServe Canary (native)

**Pros:**
- Built into KServe InferenceService spec (canaryTrafficPercent)
- No additional controller

**Cons:**
- No automated analysis — manual traffic shifting only
- No metric-based auto-rollback
- Limited step configuration

**Why not chosen:** KServe's native canary lacks automated analysis and rollback, which are critical for unattended ML model deployments.

## References

- [Argo Rollouts](https://argoproj.github.io/rollouts/)
- [AnalysisTemplate](https://argoproj.github.io/rollouts/features/analysis/)
- [ADR-006: Argo Workflows](006-argo-workflows-over-kubeflow-pipelines.md)
