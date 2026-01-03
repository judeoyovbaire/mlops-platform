# Runbook: MLflow Connection Issues

## Overview

**Severity:** Medium
**Service:** MLflow Tracking Server
**Related Alerts:** `MLflowDown`, `MLflowHighLatency`

This runbook helps diagnose and resolve MLflow tracking server connectivity issues.

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

# Test write access (from MLflow pod)
kubectl exec -n mlflow deployment/mlflow -- \
  aws s3 ls s3://mlops-platform-dev-mlflow-artifacts-<account-id>/
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
   kubectl get secret -n mlflow mlflow-db-credentials -o yaml
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
   aws iam get-role-policy \
     --role-name mlops-platform-dev-mlflow \
     --policy-name mlflow-s3
   ```

3. **Test S3 access from pod:**
   ```bash
   kubectl exec -n mlflow deployment/mlflow -- \
     aws sts get-caller-identity
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
- Configure MLflow HPA for auto-scaling
- Set up alerts for database connection pool exhaustion
