# ADR-014: AWS-First Verification Strategy

## Status

Accepted (2026-07-05)

## Context

The platform ships genuinely distinct, cloud-idiomatic Terraform for three
clouds (EKS/IRSA/Karpenter, AKS/Workload Identity/KEDA, GKE/WIF/NAP). All
three are continuously validated in CI: `terraform validate`, per-cloud plans,
Checkov policy scanning, and Infracost estimates run on every change.

End-to-end verification — actually deploying a model through CI to a live
cluster, driving canary analysis, and demonstrating automated rollback — is a
different level of assurance with a real cost: cluster time (~$12-15/day for
the dev environment), per-cloud identity wiring for CI, and multi-day
verification effort per cloud.

A claim like "works on three clouds" is only as strong as its weakest
evidence. Three unverified deployment paths are worth less than one verified
path plus two honestly-labeled architecture implementations.

## Decision

Verify **end-to-end on AWS first**. Azure and GCP remain fully maintained as
reviewed architecture:

- All three clouds keep CI validation (validate, plan, Checkov, Infracost).
- The end-to-end loop (CI deploy → MLflow registry → KServe canary →
  metric-driven auto-rollback) is exercised and evidenced on **EKS only**.
- The README carries a per-cloud verification status table so readers see
  exactly what is proven versus reviewed.

### Triggers for extending e2e verification to another cloud

- A concrete deployment target (e.g. an Azure-centric adopter or engagement).
- The AWS loop is verified and stable (no point replicating an unproven loop).
- Budget for the additional cluster time is explicitly allocated.

## Consequences

### Positive

- Verification effort concentrates where it produces evidence fastest; the
  AWS loop gets demonstrated (with recorded proof) rather than three loops
  staying theoretical.
- The verification-status table converts "multi-cloud" from an implicit
  claim into an explicit, per-cloud statement readers can trust.
- Cloud spend stays bounded (burst verification sessions, not three standing
  clusters).

### Negative

- Azure/GCP e2e regressions would not be caught until those paths are
  exercised; their deploy paths must be treated as unverified when making
  claims about them.
- Some cloud-specific wiring (e.g. AKS ingress metrics for canary analysis)
  will only be designed in detail when that cloud is verified.

### Neutral

- Renovate continues updating all three clouds' providers. If Azure/GCP bump
  noise ever outweighs value, reduce update cadence for
  `environments/{azure,gcp}` — freeze, don't delete.

## Alternatives Considered

- **Verify all three clouds** — rejected for now: ~3x cluster time and
  identity wiring for no additional proof of the platform's design; the
  clouds differ in plumbing, not architecture.
- **Drop Azure/GCP entirely** — rejected: the per-cloud implementations are
  real (not copy-paste), continuously validated, and demonstrate
  cloud-idiomatic identity/autoscaling design. Deleting them removes signal
  without adding honesty; accurate labeling achieves the same integrity.
