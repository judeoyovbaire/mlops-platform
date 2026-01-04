# Operational Runbooks

This directory contains runbooks for common operational scenarios in the MLOps platform.

## Runbook Index

| Runbook | Description | Severity |
|---------|-------------|----------|
| [Karpenter Node Not Provisioning](karpenter-node-not-provisioning.md) | Troubleshoot when GPU/training nodes don't spin up | High |
| [MLflow Connection Issues](mlflow-connection-issues.md) | Debug MLflow tracking server connectivity | Medium |

## Using These Runbooks

1. Identify the issue from alerts or user reports
2. Find the relevant runbook above
3. Follow the diagnostic steps in order
4. Escalate if resolution steps don't work

## Alert Integration

These runbooks are linked from Prometheus AlertManager alerts. When an alert fires, the runbook URL is included in the notification.

## Contributing

When adding a new runbook:
1. Use the template below
2. Include clear diagnostic steps
3. Add resolution steps with exact commands
4. Include escalation criteria
