# Model Drift Detection with Evidently AI

This example demonstrates automated model drift detection using [Evidently AI](https://www.evidentlyai.com/) integrated with the MLOps platform.

## Overview

Drift detection monitors your ML models in production to detect:
- **Data Drift**: Changes in input feature distributions
- **Prediction Drift**: Changes in model output distributions
- **Target Drift**: Changes in the actual labels (if available)

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Inference  │────▶│   S3/MinIO   │────▶│   Argo      │
│  Service    │     │  (predictions)│     │  Workflow   │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                 │
                    ┌──────────────┐             │
                    │  Evidently   │◀────────────┘
                    │  Report      │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        ┌─────▼─────┐           ┌───────▼───────┐
        │ Prometheus│           │  HTML Report  │
        │ Metrics   │           │  (S3/MinIO)   │
        └───────────┘           └───────────────┘
```

## Components

1. **drift-detection-workflow.yaml** - Argo Workflow for scheduled drift checks
2. **evidently-config.yaml** - Evidently test suite configuration
3. **prometheus-metrics.yaml** - ServiceMonitor for drift metrics

## Quick Start

```bash
# Deploy the drift detection workflow
kubectl apply -f drift-detection-workflow.yaml

# The workflow runs on a schedule (default: daily)
# Or trigger manually:
argo submit drift-detection-workflow.yaml -n argo
```

## How It Works

1. **Data Collection**: The workflow fetches recent predictions and reference data from S3/MinIO
2. **Drift Analysis**: Evidently computes statistical tests for drift detection
3. **Report Generation**: HTML reports are saved to S3 for review
4. **Metrics Export**: Drift scores are exported to Prometheus for alerting

## Drift Tests Included

| Test | Description | Threshold |
|------|-------------|-----------|
| Dataset Drift | Overall feature drift using Jensen-Shannon divergence | 0.1 |
| Column Drift | Per-feature drift detection | 0.1 |
| Prediction Drift | Output distribution changes | 0.15 |
| Data Quality | Missing values, duplicates, outliers | varies |

## Prometheus Metrics

The workflow exports these metrics:

```promql
# Overall dataset drift score (0-1, higher = more drift)
evidently_dataset_drift_score{model="sklearn-iris"}

# Per-feature drift detected (1 = drift, 0 = no drift)
evidently_feature_drift{model="sklearn-iris", feature="sepal_length"}

# Number of drifted features
evidently_drifted_features_count{model="sklearn-iris"}
```

## Alerting

Add to your PrometheusRules:

```yaml
- alert: ModelDriftDetected
  expr: evidently_dataset_drift_score > 0.3
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Model drift detected for {{ $labels.model }}"
    description: "Drift score {{ $value }} exceeds threshold"
```

## Customization

Edit `evidently-config.yaml` to customize:
- Statistical tests used
- Drift thresholds
- Features to monitor
- Report format