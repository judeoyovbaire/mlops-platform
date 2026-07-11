# IRSA Access Matrix

Every workload identity on the AWS platform: which service account maps to
which IAM role, what it can touch, and where the policy lives in Terraform.

**Why this exists:** during the first live deployment, three identity gaps
were discovered one failed deploy cycle at a time — workflow pods with no AWS
identity at all, missing KMS grants for the SSE-KMS artifact bucket, and a
serving SA that existed only on GCP. One design-review pass over a table like
this would have caught all three before any dispatch. See
[the deployment retrospective](retros/aws-deploy-retro-2026-07.md), finding
group 1.

## Standing rules

1. **S3 access always means S3 grants AND KMS grants.** Every platform bucket
   defaults to SSE-KMS (`aws:kms`) with a key policy that delegates
   authorization to IAM. A caller with `s3:PutObject` but no
   `kms:GenerateDataKey` gets `AccessDenied`; reads need `kms:Decrypt`. The
   platform pattern is a statement with both actions, `Resource = "*"`,
   conditioned on `kms:ViaService = s3.<region>.amazonaws.com` so the grant is
   only usable through S3.
2. **MLflow artifact uploads are client-side.** The tracking server brokers
   URIs; the *pipeline pods* upload to and the *serving pods* download from
   S3 directly. The MLflow server's role being correct proves nothing about
   either — each identity needs its own grants.
3. **New AWS-touching workload = new row here**, plus the design-review
   question that motivates this file: *which service account does it run as,
   and with what identity does it reach AWS?*
4. Role names follow `${cluster_name}-<component>`
   (e.g. `mlops-platform-dev-argo-workflow`).

## Workload identities (IRSA)

| Service account | Workload | AWS access | Role definition |
|---|---|---|---|
| `argo:argo-workflow` | Training/serving pipeline steps (Argo Workflows) | MLflow artifacts bucket: list, get, put, delete, multipart + KMS data-key ops (client-side MLflow uploads, rule 2) | [`modules/aws-platform/argo-workflow-irsa.tf`](../infrastructure/terraform/modules/aws-platform/argo-workflow-irsa.tf) |
| `mlops:kserve-inference` | InferenceService predictors (KServe storage-initializer downloads the model) | MLflow artifacts bucket: read-only + `kms:Decrypt` | [`modules/aws-platform/kserve-inference-irsa.tf`](../infrastructure/terraform/modules/aws-platform/kserve-inference-irsa.tf) |
| `mlflow:mlflow` | MLflow tracking server | MLflow artifacts bucket: read/write + KMS data-key ops (UI artifact serving; uploads stay client-side per rule 2) | [`modules/eks/iam.tf`](../infrastructure/terraform/modules/eks/iam.tf) (`mlflow_irsa`) |
| `monitoring:loki` | Loki (log storage) | Loki logs bucket: read/write/delete + KMS data-key ops | [`modules/eks/iam.tf`](../infrastructure/terraform/modules/eks/iam.tf) (`loki_irsa`) |
| `monitoring:tempo` | Tempo (trace storage) | Tempo traces bucket: read/write/delete + KMS data-key ops | [`modules/eks/iam.tf`](../infrastructure/terraform/modules/eks/iam.tf) (`tempo_irsa`) |
| `external-secrets:external-secrets` | External Secrets Operator | Secrets Manager: read `${cluster_name}/*` secrets + `kms:Decrypt` via Secrets Manager | [`modules/aws-platform/external-secrets.tf`](../infrastructure/terraform/modules/aws-platform/external-secrets.tf) |
| `karpenter:karpenter` | Karpenter controller | EC2 fleet/launch-template lifecycle, spot pricing, instance-profile management, node-role `iam:PassRole` | [`modules/eks/karpenter.tf`](../infrastructure/terraform/modules/eks/karpenter.tf) |
| `kube-system:aws-load-balancer-controller` | ALB/NLB controller | ELB lifecycle (AWS-managed controller policy) | [`modules/eks/iam.tf`](../infrastructure/terraform/modules/eks/iam.tf) (`aws_load_balancer_controller_irsa`) |
| `kube-system:ebs-csi-controller-sa` | EBS CSI driver | EBS volume lifecycle (AWS-managed CSI policy) | [`modules/eks/iam.tf`](../infrastructure/terraform/modules/eks/iam.tf) (`ebs_csi_irsa`) |

## Non-IRSA identities

| Identity | Used by | AWS access | Definition |
|---|---|---|---|
| `${cluster_name}-karpenter-node` (EC2 instance role) | Karpenter-provisioned nodes | EKS worker, CNI, ECR read-only, SSM core (AWS-managed policies) | [`modules/eks/karpenter.tf`](../infrastructure/terraform/modules/eks/karpenter.tf) |
| `mlops-platform-github-actions` (OIDC federation) | CI/CD pipeline (GitHub Actions) | Terraform provisioning: scoped to repo `main`/PR/environment subjects | bootstrap stack (`infrastructure/terraform/bootstrap/aws/`) |

## Gaps found while compiling this matrix

The July retro fixed the argo-workflow and kserve-inference gaps live.
Writing this table surfaced three more of the same class, fixed in the same
commit that added this file:

- **Loki** and **Tempo** write to SSE-KMS buckets but had no KMS grants —
  latent, because in-cluster reads were served from ingester-local data and
  S3 flush failures were never checked.
- The **MLflow server** role had no KMS grants for its read path (UI/registry
  artifact downloads).

That is five identities out of ten with the same missing-KMS defect —
the strongest possible argument for standing rule 1.
