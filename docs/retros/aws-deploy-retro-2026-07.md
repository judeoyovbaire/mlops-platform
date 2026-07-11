# Retrospective: First Live AWS Deployment (July 2026)

**Scope:** end-to-end pipeline-driven deployment of the platform to a live AWS
account (EKS, eu-west-1), from `deploy-infra` dispatch through model serving,
followed by full teardown.
**Outcome:** 34 distinct defects found and fixed, every one shipped through the
pipeline (commit → CI → GitOps sync), none patched by hand and left undocumented.
**Duration:** ~3 days of iterative deploy/diagnose/fix cycles.

---

## What the deployment proved

The full chain worked: Terraform provisioning → ArgoCD baseline sync → Argo
Workflows training pipeline → MLflow registry with `@champion` alias → CI
champion resolution → Kyverno admission → KServe InferenceService with the
model artifact downloaded into the serving pod via IRSA.

The training pipeline produced real, leakage-free metrics (held-out accuracy
0.9000, F1 0.8997, 5-fold CV mean 0.9417 on the train partition) and registered
`iris-classifier@champion`. Admission enforcement, artifact encryption,
memoization, and log recovery through Loki were all exercised for real.

**Not captured:** a green end-to-end smoke test against the served model. The
final blocker (Python pickle mismatch, see finding group 4) was fixed and a
compatible model retrained, but the environment was torn down before the
verifying deploy ran. The fix chain is complete in Git; the last verification
run is owed to the next deployment.

---

## Issues encountered, grouped by root-cause pattern

### 1. Identity gaps that only surfaced at runtime, one layer at a time

| Failure | Root cause | Fix |
|---|---|---|
| `Unable to locate credentials` during artifact upload | `argo-workflow` SA had no IRSA role at all — nothing ever granted workflow pods AWS identity | IRSA role scoped to the MLflow bucket (`5a35c0d`) |
| `AccessDenied` on `PutObject` after IRSA | Bucket is SSE-KMS; key policy delegates to IAM, so callers also need `kms:GenerateDataKey`/`Decrypt` | KMS statement with `kms:ViaService = s3` (`c4527b6`) |
| Predictor SA missing entirely | `kserve-inference` existed only on GCP (Workload Identity); AWS side was never built | SA + read-only IRSA in the platform module (`d3891a1`) |

Three deploy cycles to discover what one design-review question — *"which
service accounts touch S3, and with what identity?"* — would have caught.
MLflow's client-side artifact upload makes this worse than it looks: the
tracking server never uploads, so the server's IRSA role being correct proves
nothing about the pipeline pods.

### 2. Governance policies that had never been exercised

- `enforce-semantic-versioning` was **broken since the day it was written**:
  `regex_match('…', @)` binds the entire admission request (a map), so the rule
  failed variable substitution on every apply. As an `Enforce` policy it
  blocked all InferenceService deploys. The fallback idiom (`'{{@}}'` inside a
  pattern) also failed — Kyverno rebuilds the JMESPath from the pattern
  location and label keys with dots (`mlops.io/model-version`) defeat the
  reconstruction. Final form: explicit `deny` condition with a quoted key
  (`cb9357d`), verified live with both an admit and a deny case.
- The policy's intent didn't fit the platform either: MLflow registry versions
  are monotonic integers, never semver. Registry-driven deploys could never
  have passed the original rule.
- `require-model-lineage` demanded `mlops.io/mlflow-experiment-id`, which the
  champion template never set — the resolver now looks up the experiment id
  and exports it for the render (`d3891a1`).
- Kyverno vs ArgoCD drift (autogen rule injection, server-side field
  defaulting, schema-undeclared fields) required iterative `ignoreDifferences`
  work; one field (`keyless.signatureAlgorithm`) cannot be declared in Git at
  all and can only be ignored (`9a3c330`).

None of this was detectable before a real InferenceService hit the webhook,
because no test ever applied a representative manifest against the policies.

### 3. A silent Kubernetes trap: LimitRange defaulting

The mlops LimitRange declared `max: nvidia.com/gpu: "1"` with no GPU `default`.
The LimitRanger populates `default` and `defaultRequest` **from `max`** for any
resource where `default` is unset — so every container in the namespace that
didn't declare GPU got a hard `nvidia.com/gpu: 1` request injected at
admission. The predictor (and the rollout example pods) sat Pending forever in
an account that cannot launch GPU instances, and the injection was invisible in
Git: local kustomize renders showed no GPU anywhere. Diagnosed by comparing the
live object's `managedFields` output against the rendered manifest. Fix:
`1633a04` — never set `max` for an extended resource without an explicit
`default`; cap namespace GPU consumption in the ResourceQuota instead.

### 4. Training/serving environment mismatch

- Training images ran Python 3.12; every `seldonio/mlserver` image ships
  Python 3.10. The cloudpickled serving model failed to load with
  `TypeError: code expected at most 16 arguments, got 18` — 3.12 code objects
  in a 3.10 interpreter. Fix: all pipeline images moved to `python:3.10-slim`,
  with `scikit-learn` and `cloudpickle` pinned to exactly match
  `mlserver:1.7.1-mlflow`, and the champion template pinning
  `runtimeVersion: "1.7.1"` (`b90dd04`).
- The recompile then hit its own trap: `uv pip compile` uses the existing
  lockfile as preferences and carried a stale cp312 wheel hash into the cp310
  lockfile — the image build failed hash verification. Lockfiles must be
  fresh-compiled when the target interpreter changes (`839eecf`).
- Earlier in the same family: dev environment ran pandera 0.31 while the image
  pinned 0.22 (`pandera.pandas` didn't exist), and the image package layout
  didn't match the code's import paths (`0bf9170`).

### 5. Pipeline coupling to third-party infrastructure

Two deploy-model dispatches were blocked for hours by PyTorch CDN TLS failures
(`download-r2.pytorch.org` handshake errors) — inside the **pretrained**
pipeline's lockfile check and image build, which have nothing to do with
deploying the sklearn iris model. The deploy path is gated on the full validate
stage, so an unrelated ecosystem outage blocks model rollout.

### 6. GitOps interplay

- ArgoCD selfHeal reverted a manual policy hotfix within seconds. Correct
  behavior — but it silently invalidated a live verification (the "pass"
  happened in the window before the revert). Rule: on a selfHeal-enabled app,
  never test a manual apply; push to Git and test after sync.
- Mutable `:main` image tags + `IfNotPresent` created stale-image ambiguity
  during debugging. Reruns switched to immutable SHA tags.
- A local `terraform init -backend=false` (used for offline validation)
  detached the S3 backend; the destroy would have run against an empty local
  state if not re-initialized first.

### 7. Teardown friction

`terraform destroy` was blocked by: a versioned S3 bucket that refused
deletion while it held object versions, an AWS Backup vault holding RDS
recovery points, and a KServe InferenceService finalizer that wedged the
`mlops` namespace after its controller was uninstalled. Post-destroy sweep also
found three orphaned EBS volumes (eventbus PVCs) and soft-deleted Secrets
Manager entries still in their recovery window. All handled manually; the
destroy script should absorb each of these.

---

## The meta-lesson

**Every layer worked in isolation and the integration still failed eight
different ways.** `terraform validate`, unit tests (158 passing), kubeconform,
helm lint, image scans — all green, while IAM, KMS, admission policy,
scheduling, and serialization each broke at runtime. Static validation cannot
prove a distributed system; only a real deploy through the real pipeline can.
The findings ledger above is the strongest argument in this repo for
ephemeral end-to-end verification.

---

## Recommendations

1. **Training pipeline must load-test its own artifact** (highest value).
   Add a pipeline step that unpickles and invokes the serving model *inside
   the actual mlserver image* before promoting `@champion`. This one gate
   catches interpreter mismatch, library skew, and format drift at training
   time instead of deploy time.
2. **Test Kyverno policies in CI.** `kyverno apply` against fixture manifests
   with one admit case and one deny case per rule. A policy that fails
   substitution should fail the PR, not the deploy.
3. **Pin the serving runtime as an explicit contract.** One source of truth
   for Python + pickle-critical library versions, referenced by both the
   training requirements and the InferenceService `runtimeVersion`, with a CI
   check keeping the two sides in agreement.
4. **IRSA by design, not discovery.** A table in the repo mapping every SA →
   AWS-touching workload → role → policy, plus the standing rule that S3
   access on this platform always means S3 grants **and** `kms:ViaService`
   grants.
5. **Decouple deploy-model from unrelated validation.** Path-scope the
   validate stage so a model rollout does not recompile torch lockfiles or
   rebuild the pretrained image. Also removes the PyTorch-CDN single point of
   failure.
6. **Immutable image references everywhere.** Workflow defaults use digest or
   SHA tags, never `:main`; extend the signing policy to reject mutable tags.
7. **LimitRange hygiene.** Never set `max` for an extended resource without an
   explicit `default`. (Documented in the manifest; worth a standalone
   write-up — the failure mode is invisible in Git and brutal to diagnose.)
8. **Harden the destroy path.** `force_destroy` on dev buckets, delete backup
   recovery points, clear InferenceService finalizers after halting deploy
   dispatches, sweep PVC-created EBS volumes, force-delete dev secrets.

---

## Appendix: fix ledger (selected commits)

| Commit | Finding |
|---|---|
| `2697db5` | MLflow host-header validation is exact-match including port |
| `9514261` | Argo memoize keys must be ConfigMap-legal → sha256 the dataset URL |
| `d8a0b5d` | artifact-repositories ConfigMap referenced but never provisioned |
| `0bf9170` | Image package layout vs import paths; pandera version skew |
| `e0d6c51` | Workflow controller RBAC for memoize ConfigMap writes |
| `bc7f8f4` | boto3 required in every image that logs MLflow artifacts |
| `5a35c0d` | IRSA for workflow pods (MLflow S3 uploads are client-side) |
| `c4527b6` | KMS data-key grants for the SSE-KMS artifact bucket |
| `d3891a1` | Kyverno lineage annotation; kserve-inference SA + IRSA on AWS |
| `cb9357d` | Version-format policy as deny condition (pattern `{{@}}` broken) |
| `1633a04` | LimitRange GPU `max` silently injected GPU requests namespace-wide |
| `b90dd04` | Pipeline images aligned to MLServer runtime (py3.10, pinned libs) |
| `839eecf` | Fresh-compiled lockfiles (preference reuse kept stale wheel hashes) |
