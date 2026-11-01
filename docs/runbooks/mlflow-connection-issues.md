# Runbook: MLflow Connection Issues

## Overview

**Severity:** Medium
**Service:** MLflow Tracking Server
**Related Alerts:** `MLflowDown`

This runbook helps diagnose and resolve MLflow tracking server connectivity issues.

MLflow 3.16.0 (chart 1.11.7) runs cluster-internal: no authentication, no ingress, reached by `make port-forward-mlflow`. It leaves with the classic loop once the vLLM benchmark results are committed (ADR-017), and this runbook goes with it.

## Symptoms

- Training workflows failing with "Connection refused" errors
- Unable to access MLflow UI
- High latency when logging metrics/artifacts
- Model registration failures

## Diagnostic Steps

### 1. Check MLflow Pod Status

```bash
kubectl get pods -n mlflow
kubectl describe pod -n mlflow -l app=mlflow
```

### 2. Check MLflow Service

```bash
kubectl get svc -n mlflow
kubectl describe svc mlflow -n mlflow
```

### 3. Test Internal Connectivity

```bash
# From a pod in the cluster
kubectl run -it --rm debug --image=curlimages/curl -- \
  curl -v http://mlflow.mlflow.svc.cluster.local:5000/health
```

### 4. Check MLflow Logs

```bash
kubectl logs -n mlflow -l app=mlflow --tail=200
```

Common error patterns:
- `OperationalError`: Database connection issues
- `ClientError`: S3 artifact storage issues
- `TimeoutError`: Network or DNS problems

### 5. Check RDS Database

```bash
# Get RDS endpoint from Terraform outputs
aws rds describe-db-instances \
  --db-instance-identifier mlops-platform-dev-mlflow \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}'
```

### 6. Verify S3 Bucket Access

```bash
# Check bucket exists
aws s3 ls s3://mlops-platform-dev-mlflow-artifacts-<account-id>/

# Test access with the pod's IRSA identity (from MLflow pod)
kubectl exec -n mlflow deployment/mlflow -- \
  python -c "import boto3; print(boto3.client('s3').list_objects_v2(Bucket='mlops-platform-dev-mlflow-artifacts-<account-id>', MaxKeys=1)['KeyCount'])"
```

## Resolution Steps

### Pod Not Starting

1. **Check resource limits:**
   ```bash
   kubectl describe pod -n mlflow -l app=mlflow | grep -A10 "Limits\|Requests"
   ```

2. **Restart deployment:**
   ```bash
   kubectl rollout restart deployment/mlflow -n mlflow
   kubectl rollout status deployment/mlflow -n mlflow
   ```

### Database Connection Failures

1. **Verify database credentials in secrets:**
   ```bash
   # EKS: the chart reads mlflow-postgres (RDS-managed password, copied by Terraform).
   # mlflow-db-credentials is used only by the Kind setup.
   kubectl get secret -n mlflow mlflow-postgres -o yaml
   ```

2. **Test database connectivity:**
   ```bash
   kubectl run -it --rm psql --image=postgres:15 -- \
     psql "postgresql://mlflow:<password>@<rds-endpoint>:5432/mlflow" \
     -c "SELECT 1;"
   ```

3. **Check security group allows traffic:**
   ```bash
   aws ec2 describe-security-groups \
     --group-ids <mlflow-rds-sg-id> \
     --query 'SecurityGroups[0].IpPermissions'
   ```

### S3 Artifact Storage Issues

1. **Verify IRSA role:**
   ```bash
   kubectl get sa -n mlflow mlflow -o yaml | grep -A5 annotations
   ```

2. **Check IAM policy:**
   ```bash
   # Managed policy mlops-platform-dev-mlflow-s3
   aws iam list-attached-role-policies \
     --role-name mlops-platform-dev-mlflow
   ```

3. **Test S3 access from pod:**
   ```bash
   kubectl exec -n mlflow deployment/mlflow -- \
     python -c "import boto3; print(boto3.client('sts').get_caller_identity())"
   ```

### High Latency

1. **Check pod resource usage:**
   ```bash
   kubectl top pods -n mlflow
   ```

2. **Scale up if needed:**
   ```bash
   kubectl scale deployment/mlflow -n mlflow --replicas=2
   ```

3. **Check database performance:**
   - Review RDS CloudWatch metrics
   - Consider upgrading instance class

### Network Policy Blocking

Not applicable until VPC CNI network policy enforcement is enabled (the policies are synced but have no effect today).

1. **Verify network policies:**
   ```bash
   kubectl get networkpolicies -n mlflow
   kubectl describe networkpolicy -n mlflow
   ```

2. **Test from source namespace:**
   ```bash
   kubectl run -it --rm debug -n argo --image=curlimages/curl -- \
     curl -v http://mlflow.mlflow.svc.cluster.local:5000/health
   ```

## Quick Fixes

### Restart MLflow

```bash
kubectl rollout restart deployment/mlflow -n mlflow
```

### Force Database Migration

```bash
kubectl exec -n mlflow deployment/mlflow -- \
  mlflow db upgrade postgresql://mlflow:<password>@<endpoint>:5432/mlflow
```

### Clear Artifact Cache

```bash
kubectl exec -n mlflow deployment/mlflow -- \
  rm -rf /tmp/mlflow-artifacts/*
```

## Escalation

If issue persists:

1. Check **AWS RDS Events** for database issues
2. Review **CloudWatch Logs** for detailed errors
3. Escalate with:
   - MLflow pod logs
   - RDS connection test results
   - S3 access verification results

## Prevention

- Set up RDS automated backups
- Monitor RDS storage and connections
- Set up alerts for database connection pool exhaustion
