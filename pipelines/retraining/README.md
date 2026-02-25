# Automated Retraining Pipeline

Drift-triggered model retraining using Argo CronWorkflows.

## Architecture

```
Daily CronWorkflow (2 AM UTC)
  |
  +-- check-drift: Run Evidently drift detection
  |     |
  |     +-- (drift detected) --> retrain: Submit ml-training-pipeline
  |     |                           |
  |     |                           +-- validate-new-model: Check accuracy >= threshold
  |     |                                  |
  |     |                                  +-- (passes) --> promote-model: Set "champion" alias
  |     |
  |     +-- (no drift) --> [workflow ends]
```

## Configuration

Key parameters in `automated-retraining-workflow.yaml`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `drift-threshold` | `0.1` | Evidently drift score threshold to trigger retraining |
| `accuracy-threshold` | `0.9` | Minimum accuracy for the new model to be promoted |
| `model-alias` | `champion` | MLflow alias assigned to promoted models |
| `dataset-url` | Iris CSV | URL to fetch fresh training data |

## Manual Trigger

```bash
# Submit from the CronWorkflow definition
argo submit --from cronworkflow/automated-retraining -n argo

# Override parameters
argo submit --from cronworkflow/automated-retraining -n argo \
  -p drift-threshold=0.05 \
  -p accuracy-threshold=0.95
```

## Drift Detection

Uses [Evidently AI](https://www.evidentlyai.com/) to compare reference data against current production data. Drift is measured using the `DatasetDriftMetric` which computes a drift share across all features.

If the drift detection step fails (e.g., missing data files), it defaults to **no drift detected** to avoid unnecessary retraining.

## Model Promotion

When a retrained model passes the accuracy threshold:

1. The model is registered with a `retrain-candidate` alias during training
2. The `promote-model` step re-registers it with the `champion` alias
3. KServe InferenceServices referencing the `champion` alias automatically pick up the new model

## Monitoring

- Drift metrics are available in the `ML Pipeline Execution` Grafana dashboard
- Retraining workflow status appears in the Argo Workflows UI
- MLflow tracks all retraining runs with full experiment lineage
