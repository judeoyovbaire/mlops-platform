# Operational Runbooks

Runbooks for the AWS dev platform.

## Runbook Index

| Runbook | Description |
|---------|-------------|
| [Troubleshooting](troubleshooting.md) | Common failures across Terraform, KServe, MLflow, Argo, Kyverno and GPU nodes |
| [Karpenter Node Not Provisioning](karpenter-node-not-provisioning.md) | GPU or training nodes do not come up |
| [MLflow Connection Issues](mlflow-connection-issues.md) | MLflow tracking server connectivity (until MLflow leaves with the classic loop) |
| [AWS Burst Session](burst-session.md) | Deploy, check, collect evidence, tear down and sweep in one session; guardrails and the 2026-11-01 dry run |
| [AWS Environment Teardown](teardown.md) | Destroy the AWS platform cleanly (`destroy-aws.sh` procedure) |

Model rollback (deploy challenger, AnalysisRun verdict, `storageUri` rollback) is documented with its scripts in [scripts/demo/README.md](../../scripts/demo/README.md).

## Using These Runbooks

1. Identify the issue from alerts or user reports.
2. Find the relevant runbook above.
3. Follow the diagnostic steps in order.

The PrometheusRules in `infrastructure/kubernetes/monitoring.yaml` do not carry `runbook_url` annotations, so alerts do not link here.

## Adding a Runbook

Include clear diagnostic steps, resolution steps with exact commands, and the related alerts (if any), then add a row to the index above.
