# SLO/SLI Definitions

Service Level Objectives for the MLOps Platform inference and pipeline services.

## SLO 1: Inference Availability

| Field | Value |
|-------|-------|
| **SLI** | Proportion of successful (2xx) inference requests |
| **SLO Target** | 99.9% over a 30-day rolling window |
| **Error Budget** | 43.2 minutes/month |

**PromQL:**
```promql
sum(rate(revision_request_count{response_code=~"2.."}[30d]))
/
sum(rate(revision_request_count[30d]))
```

## SLO 2: Inference Latency P99 < 500ms

| Field | Value |
|-------|-------|
| **SLI** | P99 latency of inference requests |
| **SLO Target** | 99% of windows meet P99 < 500ms |
| **Error Budget** | 1% of time windows may exceed target |

**PromQL:**
```promql
histogram_quantile(0.99,
  sum(rate(revision_request_latencies_bucket[5m])) by (le)
) < 500
```

## SLO 3: Pipeline Success Rate

| Field | Value |
|-------|-------|
| **SLI** | Proportion of successful Argo Workflow runs |
| **SLO Target** | 95% over a 7-day rolling window |
| **Error Budget** | 5% of pipeline runs may fail |

**PromQL:**
```promql
sum(argo_workflows_count{status="Succeeded"})
/
sum(argo_workflows_count)
```

## Error Budget Policy

When error budget is exhausted (< 0% remaining):
1. Freeze non-critical deployments
2. Redirect engineering effort to reliability improvements
3. Conduct incident review for contributing failures

## Notes

- Metrics referenced in `infrastructure/kubernetes/monitoring.yaml` alerts for
  `model_prediction_latency_seconds` are aspirational design targets. The PromQL expressions above use metrics actually emitted by
  KServe revision proxy and Argo Workflows controller.
