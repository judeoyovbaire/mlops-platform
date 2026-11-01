# ADR-017: Pivot to LLM inference on EKS; descope multi-cloud and classic MLOps

## Status

Accepted (2026-11-01). Supersedes [ADR-004](004-multi-cloud-infrastructure-strategy.md)
and the "freeze, don't delete" guidance in [ADR-014](014-aws-first-verification.md).
The repository rename is a separate decision (see "Out of scope").

## Context

This repository set out as a multi-cloud MLOps reference platform. By July 2026
it had one verified loop: on EKS, CI deploys a model through the MLflow registry
to KServe, and a metric-gated rollback fires on a degraded challenger
([retro](../retros/aws-deploy-retro-2026-07.md), [ADR-016](016-rawdeployment-canary-and-observability.md),
[evidence](../evidence/)). Everything else was reviewed but never deployed.

An independent review in October 2026 found:

- **Large unverified surface.** Azure and GCP account for 119 files and about
  17,000 lines of Terraform, Helm values and scripts, none of which has ever been
  applied. `environments/aws/prod` has never been applied and cannot be from
  GitHub-hosted runners (private endpoint, no bastion).
- **Copies drift.** The dev/prod duplication that [ADR-015](015-shared-aws-platform-module.md)
  removed for AWS still exists on both other clouds and has already diverged.
- **Dead and idle manifests.** Some ship without the controllers or images they
  need (VPA, Gateway API stubs, oauth2-proxy, Chaos Mesh values, Feast, DVC, a
  distributed-training example). Others are installed but exercise nothing
  (tenant policies that match no namespace, Tetragon policies with no actions).
- **The headline points the wrong way.** About 80% of the repository proves
  2021-23 MLOps (sklearn, MLflow registry, KServe canary, three clouds). The
  owner's target is AI infrastructure: GPU scheduling, LLM serving, inference
  economics. The part that points there (Karpenter g5 spot pool, vLLM
  bf16/AWQ manifests, `scripts/benchmark/llm_bench.py`) has no committed
  results; `examples/llm-inference/results/` is a placeholder.
- **Docs over-claim.** A 602-line README and about 7,000 lines of docs describe
  features that are not installed.

ADR-014 kept Azure and GCP as "reviewed architecture" and said to freeze rather
than delete them. Four months on, that code has produced maintenance (Renovate
PRs, CI time, drift) and no evidence.

## Decision

Pivot **in place**: keep the history, change what `main` is.

1. **Tag the classic platform.** `v1-classic-mlops` marks the last commit before
   the descope, `d12e734`. It includes the November security fixes (59156db
   removed the internet-facing, unauthenticated MLflow), so it is the last
   classic tree that is safe to deploy. The July-verified commit `b35ef8e` is
   referenced from the retro and evidence only: it predates that fix and must
   not be deployed. The tag is pushed before the first descope change merges.
2. **Single cloud, single environment.** `main` keeps AWS dev only. Removed:
   Azure and GCP (Terraform, Helm values, CI jobs, scripts), and
   `environments/aws/prod`.
3. **Headline: LLM inference with GPU economics,** delivered through Linear
   milestone "C - LLM-Infra Pivot". Training-side work follows serving evidence.
4. **Every manifest left on `main` is installed by something and exercised by
   something.**
   - Not installed, removed: `infrastructure/kubernetes/vpa.yaml`,
     `infrastructure/kubernetes/gateway/`, `infrastructure/kubernetes/oauth2-proxy.yaml`,
     `infrastructure/kubernetes/argo-events/github-eventsource.yaml` (and its
     reference in that kustomization), `infrastructure/helm/common/{chaos-mesh,loki,tempo}-values.yaml`,
     `examples/chaos-testing/`, `examples/distributed-training/`,
     `examples/data-versioning/`, `pipelines/feature-store/` with its CI import
     step, unit test and `feast` extra.
   - Installed but not exercised, removed: `modules/aws-platform/multi-tenancy.tf`
     (policies match a label no namespace carries) and `modules/aws-platform/tetragon.tf`
     (observe-only policies, no `matchActions`).
   - Tests that assert nothing about behaviour, removed: `tests/test_infrastructure.py`,
     `tests/test_terraform_modules.py`, `tests/test_ci_integration.py`
     (regex over HCL and YAML text).
5. **The classic serving loop stays until the LLM path has its own evidence.**
   The sklearn training pipeline, MLServer runtime (Python 3.10, past EOL),
   MLflow server and the MinIO artifact store it writes to remain on `main`
   until JDH-376 commits benchmark results, then leave in one change. Moving
   Argo artifacts from MinIO to S3 would be a migration that needs the loop
   re-verified, so MinIO leaves with the loop rather than before it. Until then
   MLflow stays cluster-internal with no ingress, and JDH-410 (in-cluster
   authentication) closes with the removal rather than adding auth to a
   component on its way out. Model weights for the LLM path are S3 objects with
   a sha256 manifest (JDH-401), not registry versions.
6. **ArgoCD owns everything under `infrastructure/kubernetes/`.** Today
   Terraform (`modules/aws-platform/monitoring.tf`) applies
   `network-policies.yaml` and two of the five dashboards, while the ArgoCD
   `platform-baseline` Application reconciles the same objects with prune and
   self-heal: a standing conflict. And `platform-baseline` itself is only
   applied by hand (`infrastructure/argocd/README.md`), so on a fresh cluster
   the Enforce Kyverno policies arrive late or not at all. The fix:
   - Terraform installs the controllers, ArgoCD, and the `platform-baseline`
     Application (a new `kubectl_manifest`), so bootstrap is no longer manual.
   - The deploy script blocks until `platform-baseline` is Synced and Healthy
     before any workload (MLflow, KServe, pipelines) is deployed, so default-deny
     network policies and admission policies exist first.
   - The Terraform-applied network policies and dashboards leave Terraform state
     with `removed { lifecycle { destroy = false } }`, so an apply against a live
     cluster does not delete them out from under ArgoCD.

## Consequences

### Positive

- The verified core is what a reader sees first. Every remaining file is either
  deployed or tested and can be explained in one sentence.
- Maintenance drops: fewer Renovate PRs, a shorter CI run, no drift between
  clouds or environments.
- Bootstrap becomes one `terraform apply` plus a health wait, with policies in
  place before workloads, instead of a manual step that was easy to skip.
- The repository tells one story, and the classic platform stays a tagged,
  linkable piece of evidence rather than a deleted one.
- Removing Azure and GCP retires their scanner exceptions (`.trivyignore`
  AZU-0010/0012) and shrinks the Checkov baseline.

### Negative

- "Multi-cloud" stops being a claim this repository can make. The tag and ADR
  history show the design existed; it is no longer maintained.
- Old links into the Azure, GCP or prod directories on `main` return 404. The
  tag link in the README is the mitigation.
- A burst-session deploy waits for ArgoCD to sync before workloads start, which
  adds a few minutes to every session.
- The descope touches many places beyond the deleted directories: CI jobs for
  prod, Azure and GCP (`ci-cd.yaml`, `infracost.yaml`, `release.yaml`,
  `reusable-deploy-model.yaml`), the Makefile and deploy/destroy scripts,
  `renovate.json`, `.secrets.baseline`, `.trivyignore`, the Checkov baseline,
  `uv.lock` (feast extra), and sections of the README, `docs/README.md`,
  `docs/architecture.md`, `examples/kserve/README.md` and the
  `platform-baseline.yaml` header. JDH-407 tracks them; each removal change
  must leave CI green.

### Neutral

- [ADR-004](004-multi-cloud-infrastructure-strategy.md) becomes Superseded.
  [ADR-014](014-aws-first-verification.md) stays Accepted for its verification
  approach; only its "freeze, don't delete" guidance is reversed.
- The README is rewritten to under 150 lines with a results table first
  (JDH-408).
- Open Linear work for the removed scope is cancelled: JDH-396 (Azure/GCP
  platform modules).
- `.github/workflows/dr-test.yaml`, also listed by the review, was already
  removed in 47b754f.

## Out of scope: renaming the repository

The new name is decided: `gpu-inference-platform-eks`. The rename itself is a
separate change (Linear JDH-411, ADR-018), because GitHub's URL redirect does not cover what
the name is baked into: the AWS OIDC trust `sub` for CI
(`bootstrap/aws/main.tf`, `var.github_repo`), the cosign keyless identity and
image globs in the Enforce signature policy, every `ghcr.io/<owner>/<repo>`
image path including pinned references in pipelines and policy tests, and the
`repoURL` in `platform-baseline.yaml`. Those must change together in one
reviewed change, or CI cannot assume its role and Kyverno rejects new images.

## Alternatives Considered

### Alternative 1: Archive this repository and start a new one

**Pros:**
- Clean framing from the first commit; no legacy names or history to explain.
- Freedom to start on newer serving primitives without carrying KServe 0.16 or
  MLServer.

**Cons:**
- Loses the continuous record (about 450 commits, the July retro, sixteen ADRs,
  the evidence directory) that shows the platform was actually run to green.
  That record is the strongest signal in the repository.
- Two repositories to maintain and link.

**Why not chosen:** a tag plus a later rename gives the framing benefit without
losing the history. Newer primitives can still be adopted here by deleting the
old ones (decision 5).

### Alternative 2: Keep multi-cloud, add the LLM work alongside

**Pros:**
- No removal work; every existing claim survives.

**Cons:**
- The unverified majority keeps burying the part that matters.
- Ongoing cost in CI time, Renovate PRs and drift for code that is never applied.

**Why not chosen:** it continues the pattern the review identified as the main
problem.

### Alternative 3: Terraform owns `infrastructure/kubernetes/` instead of ArgoCD

**Pros:**
- One tool applies everything in one `terraform apply`; no wait for a sync.

**Cons:**
- ArgoCD would manage nothing, and the GitOps story would be untrue rather than
  merely thin.
- Terraform has no drift correction between applies.

**Why not chosen:** ArgoCD with prune and self-heal is the stronger control, and
the owner already runs this pattern in production. Decision 6 keeps Terraform's
one real advantage, ordering, by having the deploy script wait on ArgoCD health.

## Decisions at acceptance (2026-11-01)

- ArgoCD owns `infrastructure/kubernetes/`, with the bootstrap and health-wait
  changes in decision 6.
- MLflow, MinIO and the sklearn loop are removed later, when JDH-376 lands
  (decision 5), not now.
- Repository name: `gpu-inference-platform-eks` (rename tracked in JDH-411).

## References

- Review notes, October 2026: synthesis and recommendation (section 4), codebase
  review, tooling research, critique and career fit (kept outside the repository).
- Linear project "Principal AI-Infra Architect Pursuit", milestone
  "F - Security & Descope (Nov 2026)", stories JDH-407, JDH-408, JDH-410.
- [ADR-004](004-multi-cloud-infrastructure-strategy.md),
  [ADR-014](014-aws-first-verification.md),
  [ADR-015](015-shared-aws-platform-module.md),
  [ADR-016](016-rawdeployment-canary-and-observability.md).
