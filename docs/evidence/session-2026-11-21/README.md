# Burst session 2, 2026-11-21: CPU-only verification

Cluster `mlops-platform-dev` (EKS 1.37, AMI release `1.37.1-20261031`, eu-west-1),
deployed through the GitHub Actions OIDC role, checked from a laptop outside
the corporate proxy with the `mlops` SSO profile. Cluster time about 2 h 45 min
(17:47 UTC to the teardown), with two on-demand c6a.large Karpenter nodes for
most of it. Cost Explorer lags a day; the figure goes on JDH-409.

Figures below that have no file in this directory were read live from
`kubectl` and `aws` output during the session and not captured.

Twelve tickets had live checks pending from the 2026-11-01 cycle
(`docs/runbooks/burst-session.md`, "Session 2 plan"). Eleven checks were
completed, two of them with fixes to follow (JDH-417: the alert needs a
ServiceMonitor; JDH-418: one Alloy pod stayed Pending), and one (JDH-425)
proved its plumbing and left a design follow-up. Three fixes were
needed on the way and merged during the session: #186, #187, #188.

## Timeline (UTC)

| Time | Event |
|---|---|
| 17:37 | `deploy-infra` dispatched, run 44931102803 |
| 17:47 | Stage 1 apply; `.tflock` present (261 bytes) |
| 17:59 | Stage 1 fails: `sqs:CreateQueue` and `events:TagResource` denied for the deploy role (first live apply of the Karpenter interruption queue, JDH-415). `deploy-run-44931102803-errors.txt` |
| 18:06 | Fix applied to the bootstrap policy from the laptop (#186, `mlops-platform-gha-terraform-services` v3) |
| 18:08 | `deploy-infra` re-dispatched, run 44933873370; `.tflock` present for the whole apply, 404 after (`tflock-watch.txt`) |
| 18:27 | Deploy succeeds; platform checks start |
| 18:30 | `ml-training-md7lr` submitted; `hf-pretrained-srx6j` submitted and fails in `fetch-model` (xet cache) |
| 18:40 | `ml-training-md7lr` Succeeded (8 steps, 9m30s); champion `iris-classifier` v1 registered; `hf-pretrained-vc599` (with `HF_HOME`) submitted; `deploy-model` run 44936809366 fails in the resolve step (`models:/` source) |
| 18:47 | `hf-pretrained-vc599` Succeeded 4/4; `sentiment-classifier` v1 @champion |
| 19:05 | #187 merged; `deploy-model` run 44939062904: champion Ready, smoke step empty (attach race) |
| 19:30 | FIS experiment `EXPuAiK7bfscoMzvuY` on the training spot node; Karpenter cordons, drains and deletes the node within 50 s |
| 19:36 | #188 merged; 19:38 `deploy-model` run 44941829811 dispatched, green end to end (`setosa`) |
| 19:50 | InferenceServices and workflows deleted; teardown |

## Results by ticket

**JDH-422, S3 native locking (phase 2, first half).** `aws s3api head-object` on
`mlops-platform/dev/terraform.tfstate.tflock`: 404 before each apply, 260 to
261 bytes during Stage 1 on both runs, 404 afterwards. The lock leaves a delete
marker and a noncurrent version behind, which the phase 2 lifecycle rule will
expire. `tflock-watch.txt`.

**JDH-415, Karpenter spot interruption.** The deploy role could not create the
queue and rules (fixed in #186, see the timeline). After the deploy: queue
`mlops-platform-dev-karpenter-interruption` (SSE, 300 s retention), five
EventBridge rules ENABLED, Karpenter `INTERRUPTION_QUEUE` set and its
`interruption` controllers started at 18:21:20Z (`karpenter-log-excerpt.jsonl`).
A probe pod on the training pool brought up a spot c4.xlarge
(`training-workloads-6f7wm`, i-0f196c6ecd75f5d29). FIS
`aws:ec2:send-spot-instance-interruptions` (PT2M, `fis-experiment-template.json`)
started 19:30:52Z. Karpenter log 19:31:15: `initiating delete from
interruption message` (`messageKind: spot_interrupted`, `action:
CordonAndDrain`) and `tainted node` (`karpenter.sh/disrupted`); 19:31:41
`deleted node`. Probe pod evicted between 19:31:02 and 19:31:15; node and
NodeClaim gone by 19:31:41, before the 2-minute termination
(`fis-node-timeline.txt`, `fis-karpenter-log.jsonl`). It acted on the
interruption warning, not the rebalance recommendation. CloudWatch
(`fis-cloudwatch.txt`): SQS messages sent = received = deleted = 5 in the
19:31 minute (the 2 + 2 messages at 19:27 and 19:29 and the six
instance-state-change invocations are the probe node's own launch: that rule
fires for every instance in the region, and Karpenter discards the ones that
are not its nodes); EventBridge `Invocations` spot-interruption 1, rebalance
1, scheduled-change 1; `FailedInvocations` 0 on every rule, so the queue
policy's `SourceAccount` condition delivers. The FIS
template and its temporary IAM role were deleted after the run.

**JDH-416, AMI parity.** Node groups `general-013bebd875cc7420845cdd1b77`
(desired 2), `gpu-6fb1b82358635da4ed91d42584` (0) and
`training-b1278e703325962734bdd9be0c` (0) all report `1.37.1-20261031`;
kubelet `v1.37.1-eks-6e7947a`. Karpenter nodes on the `default` EC2NodeClass
(general and training pools) launched `ami-024d89f89bc6ec450` =
`amazon-eks-node-al2023-x86_64-standard-1.37-v20261031`. Same release on
both paths. The Renovate AMI PR (v20261112) stays for the GPU session.

**JDH-417, Kyverno alert.** Prometheus has no Kyverno target, so
`KyvernoPolicyViolations` evaluates on no data (`health=ok`, inactive).
`kyverno-svc-metrics:8000/metrics` exposes `kyverno_policy_results_total`
with `rule_result` and the other labels the alert uses
(`kyverno-policy-results-sample.txt`: 38 series, all `pass`, two shown). Fix: enable the
chart's ServiceMonitor for the admission controller and keep the alert.

**JDH-418, observability values.** Loki runs as the single `loki-0` pod with no
cache pods. Alloy containers run as uid 473. Loki (tenant `mlops`) holds one
stream per container for the train-model pod (`init`, `main`, `wait`) and
two for the champion predictor (`storage-initializer`, `kserve-container`);
"Loaded model" appears twice in Loki and twice in `kubectl logs` (two
MLServer workers), so nothing is shipped twice. New findings: both t3.large
managed nodes sit at 98 % CPU requests after the baseline (Prometheus 500m;
Loki, Karpenter, Tempo, Grafana and the KServe controller 200m each), so
Karpenter added on-demand c6a.large `general-workloads` nodes (the first for
`eventbus-default-stan-1`) and the Alloy DaemonSet pod for `ip-10-0-2-234`
stayed Pending (`Insufficient cpu`) for the whole session, so that node's
logs were not shipped. The Alloy DaemonSet has no priorityClassName.

**JDH-419, pipeline metrics.** Target
`serviceMonitor/argo/argo-workflows-controller/0` UP
(`prometheus-targets.txt`). After the training run: `argo_workflows_total_count`
by phase, `argo_workflows_gauge` (5 series),
`argo_workflows_ml_pipeline_step_duration_seconds` for all 8 steps (load-data
67.7 s, validate-data 43.8, feature-engineering 36.9, train-model 73.1,
validate-model 20.8, build-serving-model 59.2, serving-load-test 75.6,
register-model 56.6) and `argo_workflows_ml_pipeline_model_accuracy` 0.9.
`HighWorkflowFailureRate`, `PipelineFailureRate`, `PipelineStuck`, the two
`PipelineSuccessBurnRate` alerts and every `slo:*` recording rule for
`ml-pipeline-pipeline-success` evaluate with `health=ok`. Every panel query
of the `ML Pipeline Execution` dashboard returns successfully.

**JDH-420, KServe NetworkPolicy selectors.** KServe pods in `mlops` carry
`serving.kserve.io/inferenceservice=<isvc>` (plus `app=isvc.<name>-<component>`
and the `mlops.io/*` labels on the CI-deployed champion); both inference
policies select on `Exists`, so they match. Kyverno's generated
`default-deny-ingress` exists in argo, argocd, mlflow, mlops and monitoring.
Enforcement stays off, so this is a label check.

**JDH-424, mlflow-skinny training image, train to deploy.** `ml-training-md7lr`
on image `:42d5b2d` Succeeded (8 steps, 9m30s) and registered
`iris-classifier` v1 with alias `champion` (run `8e0f1c3c`). `deploy-model`
needed two fixes: MLflow 3 records the version's source as `models:/m-<id>`,
which the resolver rejected (#187 resolves it through the download-URI
endpoint); then the smoke step lost `kubectl run -i`'s attach race against a
sub-second curl and discarded the response (#188 runs the pod detached and
reads its logs). Run 44941829811: champion Ready, smoke response
`{"model_name":"iris-classifier", ... "data":["setosa"]}`.

**JDH-425, transformer in front of a predictor.**
`transformer-inferenceservice-applied.yaml`: the example with the predictor
pointed at the champion (mlflow format, MLServer v2) and the transformer
`:42d5b2d` with `--predictor_protocol=v2` and `PASSTHROUGH_MODE=true`. Ready
in about a minute. A v1 body is forwarded unchanged to the v2 predictor (422,
`inputs` required), as documented; a v2 single tensor `input-0 [2,4]` reaches
MLServer, which answers with MLflow's schema error (`Model is missing inputs
['sepal_length', ...]`); four named v2 inputs are rejected by the
transformer (`expected exactly one v2 input`). Transformer to predictor to
MLServer works. The transformer's single-tensor contract and the pyfunc
champion's named-column schema are incompatible by design, as the example's
comment anticipated: pair the transformer with the bare `model.joblib`, or
let passthrough emit named columns. Decision open.

**JDH-426, one-time Terraform blocks.** Dev state after the deploy: 263
resources, namespaces only as `module.platform.kubernetes_namespace_v1.*`.
Bootstrap state: 24 resources, all 11 `imports.tf` addresses present. Ready
for the deletion PR with JDH-422 phase 2.

**JDH-427, SHAP importance.** MLflow run `8e0f1c3c` holds
`shap_importance_scaler__petal_length` 0.1996, `scaler__petal_width` 0.1956,
`scaler__sepal_length` 0.0447, `scaler__sepal_width` 0.0063 (accuracy 0.9,
f1 0.8997). `mlflow-run-8e0f1c3c-metrics.txt`.

**JDH-412, pretrained pipeline.** The first run failed in `fetch-model`:
huggingface_hub's xet downloader caches under `HF_HOME`, and uid 1000 has no
home directory (`Permission denied (os error 13)`). `HF_HOME=/tmp/hf-home` on
the step (#187) fixed it; `hf-pretrained-vc599` Succeeded 4/4. validate-model
5/5 inferences, avg 0.039 s, p95 0.058 s. serving-load-test on
`kserve/huggingfaceserver:v0.21.0` printed `Python 3.10.12, transformers
5.13.0` and `Serving load test OK` (`hf-pretrained-vc599-serving-load-test.txt`,
recorded in `pipelines/serving-runtime-contract.yaml`). register-model registered
`sentiment-classifier` v1 @champion.

## New findings for follow-up tickets

1. **No metrics-server.** `v1beta1.metrics.k8s.io` is not registered, so the
   KServe raw-deployment HPAs log `FailedGetResourceMetric`; `minReplicas`
   and `maxReplicas` on the champion cannot act.
2. **MLflow rejects the Prometheus scrape.** `/metrics` answers 403 (`Rejected
   request with invalid Host header: <pod-ip>:5000`): `--allowed-hosts` in
   `infrastructure/helm/aws/mlflow-values.yaml` lists Service names only, and
   Prometheus scrapes by pod IP. Relabel `__address__` to the Service DNS
   name on the ServiceMonitor, or allow the pod CIDR.
3. **Baseline sizing.** See JDH-418: two t3.large are full before any
   workload; one Alloy pod never schedules.
4. **Transformer and pyfunc champion schemas** (JDH-425 follow-up).
5. **Review follow-ups from the session's PRs:** align the deploy job's
   `mlflow-skinny==2.21.3` pin with the MLflow 3 server; move `HF_HOME` into
   the pretrained Dockerfile for every step; stop `fetch_model.py` caching
   inside the output artifact.

## Files

| File | Content |
|---|---|
| `deploy-run-44931102803-errors.txt` | the six AccessDenied errors from the first Stage 1 |
| `tflock-watch.txt` | HEAD on the `.tflock` object every 45 s across both deploy runs |
| `prometheus-targets.txt` | active targets by scrape pool, with the one DOWN target |
| `kyverno-policy-results-sample.txt` | series count and two sample `kyverno_policy_results_total` lines from the metrics Service |
| `mlflow-run-8e0f1c3c-metrics.txt` | the training run's metrics, SHAP included |
| `hf-pretrained-vc599-serving-load-test.txt` | the pretrained serving-load-test output with the runtime versions |
| `karpenter-log-excerpt.jsonl` | NodeClaim provisioning and interruption-controller start lines |
| `transformer-inferenceservice-applied.yaml` | the manifest applied for JDH-425 |
| `fis-experiment-template.json` | the FIS template (deleted after the run) |
| `fis-node-timeline.txt` | node taints, probe pod and experiment state every 10 s |
| `fis-karpenter-log.jsonl` | Karpenter's three interruption lines |
| `fis-cloudwatch.txt` | SQS and EventBridge metrics for the experiment window |
