# ADR-016: One canary mechanism and RawDeployment-native observability

## Status

Accepted (2026-07-12). **Spike resolved (2026-07-13):** `canaryTrafficPercent`
is ignored under RawDeployment - a challenger update is a plain in-place
rolling update (verified live; no second deployment, no traffic split,
PREVROLLEDOUTREVISION never populates). The adopted mechanism is therefore
**post-deploy verification with automated rollback**: deploy the challenger,
judge it under real traffic with the AnalysisRun, on Failure patch
`storageUri` back to the champion. Demonstrated end-to-end: 100% error rate
measured on a degraded challenger -> verdict Failed -> automatic rollback ->
recovery, ~80 s from first measurement to healthy champion
(docs/evidence/rollback-demo-*). A true percentage traffic split needs two
InferenceServices behind weighted ALB target groups - future work, not
Milestone B.

## Context

ADR-003 chose KServe **RawDeployment** mode — no Knative. But the entire
observability and rollback contract was written against Knative revision
metrics that can never exist in this mode:

- `progressive-delivery/analysis-template.yaml`: all three canary gates
  queried `revision_request_count` / `revision_request_latencies_bucket`
- `monitoring.yaml`: core alerts and the drift-detection alerts
- `slo/*.yaml`: both inference SLOs
- The progressive-delivery Grafana dashboard

Worse, scraping was broken independently of the queries: the kserve
ServiceMonitor selected on `serving.kserve.io/inferenceservice: "true"`
(KServe sets the label value to the InferenceService *name*, never `"true"`)
and scraped the data-plane port, where `/metrics` is a 404. The auto-rollback
mechanism was provably non-functional twice over.

There were also **two parallel canary stories**: an Argo Rollout wrapping the
*training* image as a pretend model server (`progressive-delivery/
rollout.yaml`), and KServe's `canaryTrafficPercent` with no analysis attached
to it. Neither connected metrics to an automated rollback.

## Decision

### 1. Metrics come from MLServer, scraped by a PodMonitor

Verified empirically against `seldonio/mlserver:1.7.1-mlflow` (the pinned
serving runtime, see `pipelines/serving-runtime-contract.yaml`): MLServer
exposes Prometheus metrics on **port 8082**, separate from the 8080 data
plane:

- `rest_server_requests_total{method, path, status_code}`
- `rest_server_request_duration_seconds_bucket{le, path, status_code}`
  (native seconds)

A **PodMonitor** (not ServiceMonitor — the metrics port is not part of the
predictor Service) selects pods where the `serving.kserve.io/inferenceservice`
label exists, scrapes `:8082/metrics`, and relabels the pod label onto the
series as `inference_service`. Every query surface keys on that label.

### 2. One canary mechanism: KServe traffic, Argo Rollouts analysis

- **Traffic**: KServe-native `canaryTrafficPercent` on the InferenceService.
  KServe owns the predictor Deployments in RawDeployment mode; wrapping them
  in an Argo Rollout means fighting the controller.
- **Brain**: the Argo Rollouts **AnalysisTemplate** consumed as a standalone
  **AnalysisRun** — the promote workflow sets `canaryTrafficPercent`, creates
  an AnalysisRun from the template, and acts on its verdict: failure ⇒ patch
  `canaryTrafficPercent: 0` (instant rollback to stable), success ⇒ promote
  (remove canaryTrafficPercent, canary becomes the default).
- The fake Rollout (`rollout.yaml`) is **deleted**. Argo Rollouts stays
  installed solely as the AnalysisRun engine.

### 3. SLOs: Sloth CRs pre-rendered, no operator

`slo/` was excluded from the kustomization because the Sloth operator was
never installed. Running a controller to template three files is not
justified; instead the Sloth CRs stay as the **source format** and
`scripts/render-slos.sh` renders them to plain PrometheusRule manifests in
`slo/rendered/` (committed, kustomization-included). CI regenerates and
diffs — the same drift-guard pattern as the dependency lockfiles and the
serving runtime contract.

### 4. Durable telemetry: Grafana Cloud remote_write, off by default

Burst-weekend clusters vaporize metrics history on every destroy. Prometheus
gains an optional `remote_write` to Grafana Cloud's free tier, gated behind
`enable_grafana_cloud_remote_write` (default `false`) so the platform never
depends on an unprovisioned secret. A `writeRelabelConfigs` **allowlist**
ships only the series that matter (inference metrics, SLO recording rules,
model metrics, alert states) to stay far inside the 10k-series free tier.
No Mimir/Thanos: a single-cluster reference platform does not justify
self-hosted long-term storage — that judgment is the point.

## Consequences

- Every observability surface now queries metrics that demonstrably exist in
  the pinned runtime image. The Phase B cluster session must still verify
  the end-to-end path (PodMonitor targets Up, queries returning data).
- **Open item (Phase B spike):** exact traffic-split behavior of
  `canaryTrafficPercent` under RawDeployment with the ALB ingress, and the
  pod-naming convention for canary pods (the analysis template's canary
  selector is an argument so the selector can be corrected without
  restructuring). Fallback if native splitting disappoints: two
  InferenceServices behind weighted ALB target groups, same analysis brain.
- Rollback latency is bounded by AnalysisRun interval x failureLimit
  (60s x 2 by default) plus one kubectl patch — comfortably inside the
  "<2 min auto-rollback" claim, to be demonstrated in JDH-372.
