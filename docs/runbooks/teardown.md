# Runbook: AWS Environment Teardown

Full teardown of the AWS platform via `scripts/destroy-aws.sh`. Informed by
the July 2026 teardown, which needed four manual interventions the script
now automates — see
[the deployment retrospective](../retros/aws-deploy-retro-2026-07.md),
finding group 7.

## Before you start

1. **Cancel in-flight CI dispatches.** A deploy racing the teardown
   recreates resources mid-destroy; in July a deploy-model run recreated
   the InferenceService after the script's cleanup phase, and its orphaned
   finalizer wedged the `mlops` namespace for the entire terraform run.

   ```bash
   gh run list --workflow=ci-cd.yaml --status in_progress
   gh run cancel <run-id>
   ```

   The script also checks this (best-effort, needs `gh`) and warns.

2. **Valid AWS credentials** for the target account (`aws login` /
   `aws sso login`). Every phase needs them: kubectl cleanup, terraform,
   and the orphan sweep.

3. **Terraform backend attached.** If the environment directory was ever
   initialized with `-backend=false` (offline validation does this),
   re-initialize first or terraform destroys an empty local state:

   ```bash
   cd infrastructure/terraform/environments/aws/dev
   terraform init -reconfigure \
     -backend-config="bucket=mlops-platform-tfstate-<ACCOUNT_ID>" \
     -backend-config="key=mlops-platform/dev/terraform.tfstate" \
     -backend-config="region=eu-west-1" \
     -backend-config="dynamodb_table=mlops-platform-terraform-locks" \
     -backend-config="encrypt=true"
   terraform state list | wc -l   # must NOT be 0 for a live environment
   ```

## Run

```bash
./scripts/destroy-aws.sh          # interactive confirmation
./scripts/destroy-aws.sh --force  # skip prompts
```

Phases:
1. **Kubernetes cleanup** — Kyverno webhooks/policies, InferenceService
   deletion (finalizers cleared while the controller still exists),
   Karpenter nodeclaims/pools.
2. **Backup recovery point purge** — vaults cannot be deleted while they
   hold recovery points (RDS backups).
3. **Terraform destroy** — with one retry; before the retry the script
   clears finalizers on namespaces stuck `Terminating`.
4. **Orphan sweep** — Karpenter instance profiles, CloudWatch log groups,
   stray EC2 instances/ENIs, PVC-created EBS volumes, soft-deleted
   Secrets Manager entries.
5. **Verification** — checks all of the above plus cluster S3 buckets and
   backup vaults; exits nonzero listing anything that survived.

Expect 30–45 minutes; RDS, the EKS node group, and the control plane are
the slow resources.

## Terraform-side guarantees

- Dev S3 buckets set `force_destroy = true` (versioned buckets otherwise
  refuse deletion while any object versions exist).
- Dev secrets set `recovery_window_in_days = 0` (otherwise soft-deleted
  entries linger for 30 days and collide with recreated stacks).

## What intentionally survives

Bootstrap resources: the tfstate bucket, the DynamoDB lock table, its KMS
key (~$1/month), and the `mlops-platform-github-actions` OIDC role. They
are the redeploy capability — one `deploy-infra` dispatch rebuilds the
platform. KMS keys created by the environment enter `PendingDeletion`
(30-day window, no billing).

## After

```bash
kubectl config delete-context <cluster-context>
```

If verification reported issues, each check names the resource type —
delete manually and re-run the script's verification by re-invoking it
(all phases are idempotent).
