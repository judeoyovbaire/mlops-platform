# Upgrade Procedures

This document outlines procedures for upgrading platform components.

## Pre-Upgrade Checklist

Before any upgrade:

- [ ] Review release notes for breaking changes
- [ ] Backup critical data (see [Disaster Recovery](disaster-recovery.md))
- [ ] Test upgrade in non-production environment
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Verify rollback procedure

## EKS Cluster Upgrade

### Supported Versions

The platform supports EKS versions 1.28 through 1.34. Upgrade one minor version at a time.

### Procedure

1. **Check current version:**
   ```bash
   kubectl version --short
   aws eks describe-cluster --name mlops-platform-dev --query cluster.version
   ```

2. **Review addon compatibility:**
   ```bash
   aws eks describe-addon-versions --kubernetes-version 1.XX --addon-name vpc-cni
   aws eks describe-addon-versions --kubernetes-version 1.XX --addon-name coredns
   aws eks describe-addon-versions --kubernetes-version 1.XX --addon-name kube-proxy
   ```

3. **Update Terraform variable:**
   ```hcl
   # infrastructure/terraform/environments/dev/terraform.tfvars
   cluster_version = "1.XX"
   ```

4. **Plan and apply:**
   ```bash
   cd infrastructure/terraform/environments/dev
   terraform plan -out=upgrade.tfplan
   terraform apply upgrade.tfplan
   ```

5. **Upgrade node groups:**
   ```bash
   # Node groups upgrade automatically with managed node groups
   # Monitor node replacement
   kubectl get nodes -w
   ```

6. **Verify cluster health:**
   ```bash
   kubectl get nodes
   kubectl get pods -A | grep -v Running
   ```

### Rollback

EKS control plane upgrades cannot be rolled back. If issues occur:

1. Create new cluster with previous version
2. Restore workloads from backup
3. Update DNS/routing to new cluster

## Karpenter Upgrade

### Check Current Version

```bash
kubectl get deployment -n karpenter karpenter -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Procedure

1. **Update Helm values:**
   ```yaml
   # infrastructure/helm/aws/karpenter-values.yaml
   controller:
     image:
       tag: "vX.Y.Z"
   ```

2. **Apply upgrade:**
   ```bash
   helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
     --namespace karpenter \
     -f infrastructure/helm/aws/karpenter-values.yaml
   ```

3. **Verify Karpenter:**
   ```bash
   kubectl get pods -n karpenter
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50
   ```

### Rollback

```bash
helm rollback karpenter -n karpenter
```

## KServe Upgrade

### Check Current Version

```bash
kubectl get deployment -n kserve kserve-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Procedure

1. **Backup InferenceServices:**
   ```bash
   kubectl get inferenceservice -A -o yaml > inferenceservices-backup.yaml
   ```

2. **Update Helm values:**
   ```yaml
   # infrastructure/helm/aws/kserve-values.yaml
   controller:
     image:
       tag: "vX.Y.Z"
   ```

3. **Apply upgrade:**
   ```bash
   helm upgrade kserve kserve/kserve \
     --namespace kserve \
     -f infrastructure/helm/aws/kserve-values.yaml
   ```

4. **Verify InferenceServices:**
   ```bash
   kubectl get inferenceservice -A
   kubectl get pods -n mlops
   ```

### Rollback

```bash
helm rollback kserve -n kserve
kubectl apply -f inferenceservices-backup.yaml
```

## MLflow Upgrade

### Check Current Version

```bash
kubectl get deployment -n mlops mlflow -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Procedure

1. **Create database backup:**
   ```bash
   aws rds create-db-snapshot \
     --db-instance-identifier mlops-platform-dev-mlflow \
     --db-snapshot-identifier mlops-pre-upgrade-$(date +%Y%m%d)
   ```

2. **Review migration notes:**
   Check MLflow release notes for database migrations.

3. **Update deployment:**
   ```bash
   kubectl set image deployment/mlflow -n mlops \
     mlflow=ghcr.io/mlflow/mlflow:vX.Y.Z
   ```

4. **Run migrations (if required):**
   ```bash
   kubectl exec -n mlops deploy/mlflow -- mlflow db upgrade
   ```

5. **Verify MLflow:**
   ```bash
   kubectl get pods -n mlops -l app=mlflow
   curl http://mlflow.mlops.svc.cluster.local:5000/health
   ```

### Rollback

1. Restore database from snapshot
2. Rollback deployment:
   ```bash
   kubectl rollout undo deployment/mlflow -n mlops
   ```

## Argo Workflows Upgrade

### Check Current Version

```bash
kubectl get deployment -n argo argo-server -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Procedure

1. **Backup workflows:**
   ```bash
   kubectl get workflows -A -o yaml > workflows-backup.yaml
   kubectl get workflowtemplates -A -o yaml > templates-backup.yaml
   ```

2. **Apply upgrade:**
   ```bash
   helm upgrade argo-workflows argo/argo-workflows \
     --namespace argo \
     -f infrastructure/helm/aws/argo-workflows-values.yaml
   ```

3. **Verify:**
   ```bash
   kubectl get pods -n argo
   kubectl get workflows -A
   ```

### Rollback

```bash
helm rollback argo-workflows -n argo
```

## Terraform Provider Upgrades

### Procedure

1. **Update version constraints:**
   ```hcl
   # versions.tf
   required_providers {
     aws = {
       source  = "hashicorp/aws"
       version = "~> 5.X"
     }
   }
   ```

2. **Update lock file:**
   ```bash
   terraform init -upgrade
   ```

3. **Review changes:**
   ```bash
   terraform plan
   ```

4. **Apply if safe:**
   ```bash
   terraform apply
   ```

### Rollback

```bash
git checkout HEAD~1 -- .terraform.lock.hcl
terraform init
```

## Post-Upgrade Verification

After any upgrade:

1. **Run integration tests:**
   ```bash
   pytest tests/ -v
   ```

2. **Test inference endpoint:**
   ```bash
   curl -X POST "http://<endpoint>/v1/models/sklearn-iris:predict" \
     -H "Content-Type: application/json" \
     -d '{"instances": [[5.1, 3.5, 1.4, 0.2]]}'
   ```

3. **Check monitoring:**
   - Review Prometheus metrics
   - Check for error rate spikes
   - Verify latency is within bounds

4. **Verify logging:**
   ```bash
   kubectl logs -n mlops -l app.kubernetes.io/part-of=mlops-platform --tail=100
   ```

## Emergency Rollback

If critical issues occur post-upgrade:

1. **Immediate mitigation:**
   ```bash
   # Scale down affected component
   kubectl scale deployment/<name> -n <namespace> --replicas=0
   ```

2. **Rollback:**
   ```bash
   # Helm-managed
   helm rollback <release> -n <namespace>

   # Deployment
   kubectl rollout undo deployment/<name> -n <namespace>
   ```

3. **Restore data if needed:**
   See [Disaster Recovery](disaster-recovery.md)

4. **Post-incident:**
   - Document root cause
   - Update runbooks
   - Schedule retry with fixes

## Related Documentation

- [Architecture](architecture.md)
- [Disaster Recovery](disaster-recovery.md)
- [Troubleshooting](troubleshooting.md)
