# ADR-015: Shared aws-platform Module for the Kubernetes Platform Layer

## Status

Accepted (2026-07-05) — supersedes [ADR-012](012-terragrunt-evaluation.md)

## Context

The AWS dev and prod environments shipped 14 of 19 `.tf` files as byte-for-byte
copies (Karpenter pools, Kyverno/Tetragon policies, the monitoring stack, core
Helm releases, namespaces, storage classes, quotas). Copy-drift was not a
theoretical risk — production Karpenter EC2NodeClasses ran tagged
`Environment: dev` because the prod file was a stale copy of dev's.

ADR-012 evaluated Terragrunt for this problem and deferred, keeping the
duplication. The 2026-07 architecture review flagged the duplication (and the
tag bug it caused) as a concrete finding.

## Decision

Extract the environment-agnostic platform layer into a native Terraform
module, `modules/aws-platform`, consumed by both AWS environments:

- **Moved into the module** (14 files): argo-events, cost-observability,
  external-secrets (incl. its IRSA), gpu-monitoring, kyverno, monitoring,
  multi-tenancy, namespaces, progressive-delivery, storage, tetragon,
  karpenter, helm-core, and the module's own data sources.
- **Environment differences become typed inputs**, not file divergence:
  `environment` (tags/labels), `minio` sizing object (standalone vs
  distributed HA), `argocd_extra_values_files` (prod HA overlay),
  `grafana_admin_password` (generated in each environment's secrets.tf).
- **`eks = module.eks` is passed wholesale** as an object input — the module
  consumes the cluster identity and IRSA/bucket outputs without re-declaring
  a dozen individual variables.
- **Stayed in the environments**: eks.tf (genuinely different sizing/HA),
  secrets.tf, providers/backend, outputs, variables. Helm chart versions
  continue to flow from the shared `helm-versions.auto.tfvars` through the
  environment into the module.
- **`moved` blocks** in both environments map every extracted resource
  address (65 of them) to its new module path, so existing state migrates
  in-place instead of planning destroy/recreate.

Native modules over Terragrunt (revisiting ADR-012): the duplication was in
*resources*, which a module solves directly; Terragrunt's strengths
(DRY backend/provider config, dependency orchestration) address a different,
smaller problem here and add a wrapper tool the repo otherwise doesn't need.

## Consequences

### Positive

- A platform change (policy, chart, pool) is made once and reviewed once;
  dev/prod divergence is impossible except through explicit inputs.
- The `Environment: dev`-in-prod bug class is structurally eliminated.
- Azure and GCP can follow the same pattern (`modules/azure-platform`,
  `modules/gcp-platform`) — deferred until after AWS e2e verification
  (ADR-014), since their kyverno/monitoring files differ structurally and
  parameterizing them is real work, not a copy of this change.

### Negative

- One more level of indirection when reading the AWS environments.
- The first `terraform plan` after this change exercises 65 `moved` blocks —
  it must be reviewed carefully (expected: moves only, no changes) during the
  next cluster session before any apply.

### Neutral

- CI validation coverage is unchanged: both environments still
  `terraform validate` + plan + Checkov on every change.
