# Runbook: Karpenter Node Not Provisioning

## Overview

**Severity:** High
**Service:** Karpenter
**Related Alerts:** `KarpenterNodeProvisioningFailed`, `PodPendingTooLong`

This runbook helps diagnose and resolve issues when Karpenter fails to provision nodes for pending workloads.

## Symptoms

- Pods stuck in `Pending` state for more than 5 minutes
- GPU/training workloads not starting
- Karpenter logs showing provisioning errors

## Diagnostic Steps

### 1. Check Pending Pods

```bash
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

### 2. Describe Pending Pod

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look for:
- `FailedScheduling` events
- Resource constraints (CPU, memory, GPU)
- Node selector/affinity mismatches
- Taint/toleration issues

### 3. Check Karpenter Controller Logs

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller --tail=100
```

Common error patterns:
- `InsufficientInstanceCapacity`: AWS capacity issue
- `UnauthorizedOperation`: IAM permission problem
- `Unsupported`: Invalid instance type for region

### 4. Verify NodePool Configuration

```bash
kubectl get nodepools
kubectl describe nodepool <name>
```

Check:
- Instance requirements (types, categories)
- Capacity type (spot/on-demand)
- Resource limits (not exceeded)

### 5. Check EC2NodeClass

```bash
kubectl get ec2nodeclasses
kubectl describe ec2nodeclass <name>
```

Verify:
- AMI is valid and available
- Subnets have available IPs
- Security groups exist
- IAM role is configured

### 6. Check AWS Capacity

```bash
aws ec2 describe-instance-type-offerings \
  --region eu-west-1 \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=g4dn.xlarge" \
  --query "InstanceTypeOfferings[].Location"
```

## Resolution Steps

### SPOT Capacity Issues

If SPOT instances aren't available:

1. **Check SPOT pricing and availability:**
   ```bash
   aws ec2 describe-spot-price-history \
     --instance-types g4dn.xlarge \
     --product-descriptions "Linux/UNIX" \
     --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
     --region eu-west-1
   ```

2. **Temporarily allow on-demand fallback:**
   Edit the NodePool to include both capacity types:
   ```yaml
   requirements:
     - key: "karpenter.sh/capacity-type"
       operator: In
       values: ["spot", "on-demand"]
   ```

### IAM Permission Issues

1. **Verify Karpenter role:**
   ```bash
   kubectl get sa -n karpenter karpenter -o yaml
   ```

2. **Check IAM role trust relationship:**
   ```bash
   aws iam get-role --role-name mlops-platform-dev-karpenter \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. **Verify attached policies:**
   ```bash
   aws iam list-attached-role-policies \
     --role-name mlops-platform-dev-karpenter
   ```

### Subnet IP Exhaustion

1. **Check available IPs:**
   ```bash
   aws ec2 describe-subnets \
     --filters "Name=tag:karpenter.sh/discovery,Values=mlops-platform-dev" \
     --query "Subnets[].{ID:SubnetId,AZ:AvailabilityZone,Available:AvailableIpAddressCount}"
   ```

2. **If IPs are low, consider:**
   - Adding new subnets
   - Using larger CIDR blocks
   - Enabling VPC CNI prefix delegation (already enabled)

### Node Stuck in NotReady

If nodes provision but stay NotReady:

1. **Check node conditions:**
   ```bash
   kubectl describe node <node-name>
   ```

2. **Check kubelet logs:**
   ```bash
   # SSH to node or use SSM
   journalctl -u kubelet -f
   ```

3. **Check for CNI issues:**
   ```bash
   kubectl logs -n kube-system -l k8s-app=aws-node --tail=100
   ```

## Escalation

If issue persists after following these steps:

1. **Check AWS Service Health Dashboard** for region-wide issues
2. **Review Karpenter GitHub issues** for known bugs
3. **Escalate to platform team** with:
   - Karpenter controller logs
   - Pending pod descriptions
   - NodePool/EC2NodeClass configurations

## Prevention

- Monitor SPOT interruption rates
- Set up alerts for `karpenter_nodepools_limit` approaching 80%
- Regularly review and update instance type lists
- Test provisioning with manual workloads after changes
