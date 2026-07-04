# ADR-013: Descope Drift-Triggered Retraining

## Status

Accepted (2026-07-04)

## Context

The platform shipped a drift-detection component and an automated
drift → retrain loop: a monitoring service computing drift statistics, a
`DataDriftDetected` PrometheusRule, an Argo Events EventSource/Sensor, and an
automated retraining Workflow.

An architecture review (2026-07) found the loop broken at several independent
links:

- The drift detector deployed as a **no-op**: `REFERENCE_DATA_PATH` /
  `PRODUCTION_DATA_PATH` were never set, so the pod logged "no data paths
  configured" every cycle and computed nothing. Its container image was never
  built by CI.
- **Metric name mismatch**: the detector emitted `data_drift_score`, alerts
  queried `model_data_drift_score`, and the example workflow emitted
  `evidently_dataset_drift_score`.
- The Alertmanager route the retraining trigger depended on was **never
  defined**, and the EventSource/Sensor manifests were applied by nothing.
- The retraining Workflow imported `evidently` inside an image that did not
  install it, swallowed the resulting exception in a bare `except`, and
  reported **"no drift" forever**. Its `resource:` template declared output
  parameters that can never resolve.
- Most fundamentally: **nothing captures production inference data**, so
  there was no dataset for drift computation even if every link above worked.

Repairing the loop end-to-end was estimated at ~2 weeks (including building
production data capture). Meanwhile the platform's verification priority is
the core serving loop: deploy → canary analysis → automated rollback.

## Decision

Descope drift-triggered retraining from the platform:

- Remove the drift-detection Deployment/ServiceMonitor, the retraining
  Workflow, the Argo Events trigger, and the drift alerts/analysis gates.
- **Keep the statistical core** (`components/drift-detection/drift_detector.py`)
  and its property-based tests as a standalone library: the KS/PSI/JS/Cramér's-V
  implementation is correct, tested, and reusable.
- Reinvest the effort in end-to-end verification of the serving loop and in
  GPU-verified LLM inference (see Roadmap).

## Consequences

### Positive

- No deployed-but-broken surface: everything running in a cluster does what
  its documentation says.
- ~2 weeks of effort redirected to the highest-value verification work.
- The retained library remains available for future integration.

### Negative

- The platform no longer claims automated retraining. Model performance
  monitoring is reduced to the aspirational alert contract documented in
  `monitoring.yaml`.

### Neutral

- Re-scoping requires production inference-data capture first (request
  logging at the serving layer). If/when that exists, integration can be
  reconsidered with a much smaller design: scheduled batch drift reports
  before event-driven retraining.

## Alternatives Considered

- **Fix the loop end-to-end** — rejected: highest-effort option, and the
  2026 platform priority is verified serving (deploy/canary/rollback) and
  LLM inference rather than classic-MLOps drift automation.
- **Simplify to a scheduled drift-report CronWorkflow** — viable middle
  ground, rejected for now for the same prioritization reason; noted as the
  preferred first step if drift is revisited.
