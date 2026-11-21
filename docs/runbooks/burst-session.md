# Runbook: AWS Burst Session

Every GPU phase is a burst session: build the platform, measure, commit the
evidence, and tear it down the same day. This runbook is the repeatable
procedure on the project's own account (183590992229, eu-west-1). It was
written from the first dry run on 2026-11-01 and confirmed by a clean cycle the
same evening; both are recorded at the end.

**Requires** PRs #121, #122 and #123 on `main` (the dry-run fixes; #123 moves
Argo artifacts to S3 and fixes MLflow memory). Without them the deploy fails as
described in the last section.

## Guardrails that are always on

| Guardrail | Setting |
|---|---|
| Monthly budget | `mlops-platform-gpu-monthly`, 110 USD, email at 50% and 100% of actual spend |
| Idle guard | `mlops-platform-idle-guard-daily`, 3 USD per day, email at 100% of actual spend. Idle days cost cents (S3 state, KMS), so it only fires when something was left running. |
| Cost Anomaly Detection | Default services monitor, daily subscription |
| Karpenter GPU pool | `limits`: 2 GPUs, 16 vCPU, 80Gi; spot only; `consolidationPolicy: WhenEmptyOrUnderutilized` after 1 minute; `expireAfter: 4h` |
| Spot quota | All G and VT Spot Instance Requests: 8 vCPU, which binds before the pool's 16 vCPU limit: two g5.xlarge, or one g5.2xlarge, at a time |

The budgets and the anomaly monitor were created by hand, outside Terraform,
and survive teardown. They run on billing data that lags by hours, so they are
next-day backstops, not in-session alarms. `expireAfter: 4h` replaces a node
while pods still need it; it does not stop spend. Keep any single benchmark
under 4 hours, and treat the teardown as the real stop.

## Before the session

1. **Sign in.** `aws sso login --profile mlops`. Use only the `mlops` profile.
   The session lasts about an hour, so sign in again before the teardown
   (see [Teardown](#teardown)).
2. **Network.** The EKS API endpoint is not reachable through Zscaler (every
   request is reset). Turn Zscaler off for the session. Without cluster API
   access, the teardown cannot remove the Helm and Kubernetes resources.
   AWS CloudShell is the alternative, with two caveats: install the CI
   Terraform release there (see step 3), and put the provider cache under `/tmp`
   (`export TF_DATA_DIR=/tmp/tf-dev TF_PLUGIN_CACHE_DIR=/tmp/tf-plugins`),
   because the 1 GB home directory cannot hold the providers.
3. **Local tools.** Terraform must read state written by CI, so use the
   release pinned in `TERRAFORM_VERSION` (`.github/workflows/ci-cd.yaml`;
   Renovate bumps it), both for the teardown and for the sweep's
   `terraform state list`. With tfenv: `tfenv install <that version>`, then
   use it for the session.
4. **CA bundle (Zscaler on only).** The `mlops` profile has no `ca_bundle`;
   while Zscaler is on, prefix AWS commands with
   `AWS_CA_BUNDLE=$HOME/.aws/system-ca-bundle.pem`.
5. **Nothing running.** Both lists are empty, and so is the cluster list:
   ```bash
   gh run list --workflow=ci-cd.yaml --status in_progress
   gh run list --workflow=ci-cd.yaml --status queued
   aws eks list-clusters --profile mlops
   ```
6. **No merges during the session.** The dispatch shares the `main`
   concurrency group with push runs. It waits behind an in-progress push run
   (about 10 minutes after a merge), and a further merge while it waits
   cancels it.

## Deploy

Deploys run in GitHub Actions with the OIDC deploy role, which is the IAM that
the session tests. (`make deploy-aws` in the README runs the same Terraform
locally with your SSO credentials, so it skips testing that role.)

```bash
gh workflow run ci-cd.yaml --ref main \
  -f cloud=aws -f environment=dev -f action=deploy-infra
gh run list --workflow=ci-cd.yaml --event workflow_dispatch -L1   # note the run id
gh run watch <run-id>
```

What the run does, after the validation jobs it waits on:

| Step | What happens | First dry run |
|---|---|---|
| Terraform Plan (AWS) | Plans only `module.eks` while no cluster exists | about 1 min |
| Stage 1 (EKS) | VPC, NAT, EKS 1.37, managed node groups, RDS, S3, KMS, IRSA, access entries | VPC and EKS 12 min; RDS 8 min more (the first attempt stopped at RDS) |
| Stage 2 (Kubernetes) | Controllers via Helm, then the ArgoCD `platform-baseline` Application and its gate (Synced and Healthy, capped at about 21 minutes), then MLflow | 17 min, about 11 of them the gate waiting on an OOMKilled ArgoCD controller; expect 6 to 8 min with #122 |

The clean cycle took 33 minutes from dispatch: about 13 for queueing and the
validation jobs, 11 for Stage 1 and 7.5 for Stage 2. Allow 45 minutes; a wait
behind a push run comes on top.

### Cancel or recover

- Cancel a run with `gh run cancel <run-id>`.
- A cancelled `terraform apply` can leave the state lock held; the next init
  or the teardown then fails on the lock. Clear it with
  `terraform force-unlock <lock-id>` (the id is in the error).
- After a failed deploy, either fix and dispatch again (the run resumes from
  state, as it did on 2026-11-01), or tear down as is.
- Before any teardown, make sure no deploy is running (see
  [teardown.md](teardown.md), "Before you start").

## Checks on the live cluster

```bash
export AWS_PROFILE=mlops AWS_REGION=eu-west-1
export KUBECONFIG=$(mktemp)
aws eks update-kubeconfig --name mlops-platform-dev --kubeconfig "$KUBECONFIG"
```

Your IAM Identity Center admin role has a cluster-admin access entry
(`human_admin_role_arns`), so the EKS console also shows workloads.

1. **Baseline.** `kubectl -n argocd get application platform-baseline` shows
   `Synced` and `Healthy`. If it stays `OutOfSync`, list the drifting
   resources and compare live against Git; server-side defaults belong in
   `ignoreDifferences` or written out in Git.
   ```bash
   kubectl -n argocd get application platform-baseline \
     -o jsonpath='{range .status.resources[?(@.status=="OutOfSync")]}{.kind}/{.namespace}/{.name}{"\n"}{end}'
   ```
2. **Pods.** This prints "No resources found" when every pod is running or
   finished; also scan the READY column of `kubectl get pods -A` for `0/1`.
   ```bash
   kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   ```
   For any crash loop, check `lastState.terminated.reason` first; two of the
   first session's failures were `OOMKilled`.
3. **Event bus.** `kubectl -n argo-events get pods` shows the three
   `eventbus-default-stan-*` pods Running, not just the EventBus `Healthy`.
4. **Nodes.** `kubectl get nodeclaims`. A Karpenter node that nobody asked for
   is a sizing problem; on 2026-11-01 the Loki chunks cache (9830Mi request)
   pulled in an on-demand r6a.large (JDH-418).

### Session 2 plan: CPU-only verification (planned for 2026-11-24 or later)

Twelve tickets left live checks behind after the 2026-11-01 cycle. This
session closes them on the CPU platform, at about 0.5 USD per cluster-hour,
and leaves the GPU work (JDH-376, JDH-399, JDH-421) for its own session on a
fresh budget. Budget about 3 cluster-hours plus the 45-minute deploy: 2 to 3
USD. Not on a Monday morning: Renovate opens its batch before 08:00 London and
now automerges green PRs, and every push to `main` queues behind or cancels the
dispatch (rule 6 above). Before dispatching, `gh pr list` must show no open PR
that can still automerge.

**Done on 2026-11-21, do not repeat:** local `backend.conf` with
`use_lockfile = true`, `terraform init -reconfigure` in dev and bootstrap
against the S3 state, uv 0.13.9. **Still to do before the session:** install
the `TERRAFORM_VERSION` release so it survives the shell (`tfenv install
1.17.2`, or copy the verified binary to `~/bin`); `~/bin/terraform` is 1.14.5.

Working order, with the ticket each step closes. Capture the command output
for the evidence PR as you go.

1. **Deploy** (45 min). While Stage 1 applies, from the laptop:
   `aws s3api head-object --bucket mlops-platform-tfstate-183590992229
   --key mlops-platform/dev/terraform.tfstate.tflock` answers 200 during the
   apply and 404 after it (the lock leaves a delete marker and a noncurrent
   version behind, which the phase 2 lifecycle rule will expire). JDH-422
   phase 2, first half.
2. **Platform** (the four checks above), then:
   - Nothing Pending in `monitoring`; `loki` Running without a cache pod and
     without an unrequested node (JDH-418). `kubectl -n monitoring get pods
     -l app.kubernetes.io/name=alloy -o jsonpath='{.items[*].spec.securityContext.runAsUser}'`
     prints 473 for every pod.
   - Prometheus targets: port-forward `svc/prometheus-operated 9090`, then
     `/targets`. `argo-workflows-workflow-controller` must be UP (JDH-419);
     list anything DOWN. There is no Kyverno target: nothing in the repo
     creates a ServiceMonitor for it, so `KyvernoPolicyViolations` cannot
     fire today (JDH-417).
   - Kyverno metric: `kubectl -n kyverno port-forward svc/kyverno-svc-metrics 8000`,
     then `curl -s localhost:8000/metrics | grep kyverno_policy_results_total`.
     If the metric and the labels the alert uses are there, the fix is a
     ServiceMonitor on that Service; if not, drop the alert (JDH-417).
3. **Classic loop** (JDH-424, JDH-427, JDH-419, JDH-420): `make deploy-pipeline`,
   `make run-pipeline`, `argo -n argo watch @latest`. Then:
   - MLflow (`make port-forward-mlflow`): the run has four
     `shap_importance_*` metrics for Iris (JDH-427) and the champion is
     registered (the mlflow-skinny image, JDH-424).
   - Prometheus: `argo_workflows_total_count`, `argo_workflows_gauge` and
     `argo_workflows_ml_pipeline_*` return series; the pipeline SLO
     recording rules and `HighWorkflowFailureRate` evaluate; every panel of
     the ML pipeline dashboard renders (JDH-419).
   - `gh workflow run ci-cd.yaml --ref main -f cloud=aws -f environment=dev
     -f action=deploy-model`, then `kubectl -n mlops get inferenceservice`
     Ready and one prediction through port-forward (JDH-424 acceptance).
   - `kubectl -n mlops get pods --show-labels` on the predictor: the
     `serving.kserve.io/inferenceservice` label is present, so the
     `Exists` selector matches (JDH-420; enforcement stays off, so this is a
     label check only). `kubectl get networkpolicy -A` shows the generated
     `default-deny-ingress` in the new namespaces.
   - One log line arrives in Loki once: query a predictor pod's logs in
     Grafana Explore and count streams (JDH-418).
4. **Transformer** (JDH-425): copy `examples/kserve/transformer-inferenceservice.yaml`,
   replace the predictor `storageUri` (a `gs://` placeholder) with the
   champion's S3 URI from MLflow, and add `PASSTHROUGH_MODE: "true"` to the
   transformer's `env` (the champion bundles the preprocessor, so a
   transforming pass would scale twice). Apply it and send one v1 request.
   Record that the plumbing works; the bare-model variant with
   `--predictor_protocol=v2` is a follow-up, Jude's call.
5. **Pretrained** (JDH-412): nothing deploys this WorkflowTemplate, so
   `kubectl -n argo create -f pipelines/pretrained/hf-pretrained-workflow.yaml`
   creates the template and submits one run (the file holds both; on a rerun
   use `argo -n argo submit --from workflowtemplate/hf-pretrained-pipeline`).
   Watch the serving-load-test on huggingfaceserver v0.21 for
   text-classification, and copy the versions it prints into
   `pipelines/serving-runtime-contract.yaml` in the evidence PR.
6. **Node AMIs and spot interruption** (JDH-416, JDH-415). Managed node
   groups carry a generated suffix, so list them first:

   ```bash
   for ng in $(aws eks list-nodegroups --cluster-name mlops-platform-dev --query 'nodegroups[]' --output text); do
     aws eks describe-nodegroup --cluster-name mlops-platform-dev --nodegroup-name "$ng" \
       --query '[nodegroup.nodegroupName,nodegroup.releaseVersion]' --output text
   done                                              # every line ends 1.37.1-20261031
   kubectl run ami-probe --image=registry.k8s.io/pause:3.10 \
     --overrides='{"spec":{"nodeSelector":{"node-type":"training"},
       "tolerations":[{"key":"workload","operator":"Exists","effect":"NoSchedule"}]}}'
   kubectl get nodeclaims -o wide                    # the new spot node on the training pool
   aws ec2 describe-images --image-ids <ami-id> --query 'Images[0].Name'   # ends in v20261031
   ```

   `1.37.1-20261031` is the pinned `eks_ami_release`; both node paths must
   show the same date. Then the interruption test on that instance:
   Karpenter's log must show the interruption controller started
   (`kubectl -n karpenter logs deploy/karpenter | grep -i interruption`), and
   an AWS FIS experiment with action `aws:ec2:send-spot-instance-interruptions`
   (target type `aws:ec2:spot-instance`, the instance ARN,
   `durationBeforeInterruption` PT2M, an experiment role with the managed
   policy `AWSFaultInjectionSimulatorEC2Access`) must produce cordon and
   drain on the node before it terminates. FIS sends a rebalance
   recommendation at once and the interruption warning two minutes later;
   Karpenter may start draining on the first, so cite the reason from its
   log in the evidence. Delivery through the queue's `SourceAccount`
   condition shows in CloudWatch, not in the queue (Karpenter deletes what it
   reads): `AWS/SQS` `NumberOfMessagesReceived` and `NumberOfMessagesDeleted`
   for `QueueName=mlops-platform-dev-karpenter-interruption` (Sum, 1 min) go
   up, and `AWS/Events` `FailedInvocations` on the Karpenter rules stays 0.
   Delete the probe pod and the FIS template when done.
7. **State hygiene** (JDH-426): `terraform state list | grep kubernetes_namespace`
   in dev shows only `kubernetes_namespace_v1.*`; `terraform state list` in
   bootstrap/aws holds all 11 resources named in `imports.tf`. Both were
   initialised against S3 on 2026-11-21.
8. **Evidence PR** before teardown: outputs from the steps above under
   `docs/evidence/session-2026-xx-xx/`, the contract-file versions, and the
   Linear items ticked. Then **teardown** as below; the sweep adds a check
   that no `.tflock` object remains current in the state bucket.

**After the session, on Jude's go** (one bootstrap apply, one PR): JDH-422
phase 2 (drop the DynamoDB table, its IAM statement, outputs and every
`dynamodb_table` backend entry; add the delete-marker expiration to the state
bucket lifecycle) together with JDH-426 (delete `imports.tf`, `moved.tf` and
the three `removed` blocks). Close JDH-412, 415, 416, 417, 418, 419, 420,
424, 425, 427 with their evidence; JDH-406 closes after the first automerge
is observed.

**GPU session (separate, next):** JDH-376 (vLLM on g5, the benchmark),
JDH-399 (DCGM on the Karpenter pool, vLLM `/metrics`, GPU alerts on real
series), JDH-421 (vLLM v0.32 starts on g5, auth on every route), and the
Renovate AMI PR (v20261112, `gpu-session-required`) merged once the NVIDIA
driver on that release has run the vLLM smoke.

## Evidence

Commit results on a branch and open a PR before teardown (`main` rejects
direct pushes): benchmark output under `examples/llm-inference/results/`, plus
startup times, kernel lines and the session's cost. Screenshots and
AnalysisRun YAML go under `docs/evidence/`.

## Teardown

There is no CI destroy action; the teardown runs locally (or in CloudShell)
with cluster API access and the Terraform release CI pins (`TERRAFORM_VERSION`
in `.github/workflows/ci-cd.yaml`).

Right before the teardown, sign in again and confirm cluster access. Both go
stale during a session: the SSO session lasts about an hour, and Zscaler may
have come back on.

```bash
aws sso login --profile mlops
export AWS_PROFILE=mlops AWS_REGION=eu-west-1 KUBECONFIG=$(mktemp)
aws eks update-kubeconfig --name mlops-platform-dev --kubeconfig "$KUBECONFIG"
kubectl get nodes          # must answer, not "connection reset by peer"
cd infrastructure/terraform/environments/aws/dev
terraform init -reconfigure \
  -backend-config="bucket=mlops-platform-tfstate-183590992229" \
  -backend-config="key=mlops-platform/dev/terraform.tfstate" \
  -backend-config="region=eu-west-1" \
  -backend-config="dynamodb_table=mlops-platform-terraform-locks" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
cd -
./scripts/destroy-aws.sh --force
```

Re-initialise first: an environment directory initialised with
`-backend=false` (offline validation does this) destroys an empty local state.
See [teardown.md](teardown.md) for what the script does. Its preflight stops
before changing anything if Terraform cannot read the state (an expired SSO
token), if the cluster exists but the state is empty, or if the cluster API
does not answer. If `terraform destroy` fails twice, the script exits non-zero
without its final sweep and verification; fix the cause and run it again.

It took 15 minutes on the first dry run (including six orphaned EBS volumes
from persistent volume claims) and 12.5 minutes on the clean cycle.
teardown.md's 30 to 45 minutes allows for a wedged namespace or a retry.

## Sweep

Each count should be `0`, the only bucket should be the state bucket, and the
dev state should hold no resources. The VPC count assumes nothing else lives in
the account.

```bash
export AWS_PROFILE=mlops AWS_REGION=eu-west-1
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations)'
aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available,deleting --query 'length(NatGateways)'
aws ec2 describe-addresses --query 'length(Addresses)'
aws elbv2 describe-load-balancers --query 'length(LoadBalancers)'
aws ec2 describe-volumes --query 'length(Volumes)'
aws ec2 describe-network-interfaces --query 'length(NetworkInterfaces)'
aws rds describe-db-instances --query 'length(DBInstances)'
aws eks list-clusters --query 'length(clusters)'
aws ec2 describe-vpcs --filters Name=is-default,Values=false --query 'length(Vpcs)'
aws secretsmanager list-secrets --query 'length(SecretList)'
aws logs describe-log-groups --log-group-name-prefix /aws/eks/mlops-platform-dev --query 'length(logGroups)'
aws s3api list-buckets --query 'Buckets[].Name' --output text
(cd infrastructure/terraform/environments/aws/dev && terraform state list | wc -l)
```

Customer-managed KMS keys left in `PendingDeletion` are expected (the module
schedules them on destroy) and cost nothing.

The next day, read the session's cost in Cost Explorer, record it with the
evidence (results file or PR body) and on the Linear issue, and confirm that
days without a session show only S3 and KMS.

## First dry run, 2026-11-01

A CPU-only session over three deploys. The cluster ran from about 16:05 to
18:19 UTC; at the platform's on-demand rates (EKS control plane, two t3.large,
one NAT gateway, db.t3.small, plus an r6a.large for the last hour, public IPv4
and EBS) that is roughly 1 to 1.5 USD. Cost Explorer reports by day, so this
session is inside the 2026-11-01 figure below together with the clean cycle.

The findings, fixed in #121, #122 and #123:

| Failure | Cause | Fix |
|---|---|---|
| Stage 1: `KMSKeyNotAccessibleFault` creating the MLflow RDS instance | RDS describes `aws/secretsmanager` as the caller for managed master passwords; the deploy role may only use `Project`-tagged keys (JDH-404) | RDS uses the platform key for the secret and Performance Insights; deploy role regains `kms:DescribeKey` (#121) |
| EKS console "Unauthorized" for the SSO admin role | The access entry for `:root` covers only the root user | IAM Identity Center admin role gets a cluster-admin access entry (#121) |
| ArgoCD application controller `OOMKilled` | 512Mi too small for the cluster cache on first sync | 1Gi request / 2Gi limit (#122) |
| Kyverno rejected `add-default-networkpolicy` | Kyverno 1.19 admits generate rules only when the submitter has Kubernetes RBAC for the generated kind; the CI role is an admin via an EKS access policy | Policy moved to the ArgoCD baseline, CREATE only, excluding namespaces the baseline already covers (#122) |
| Baseline stuck `OutOfSync` | Server-side defaults (Kyverno `signatureAlgorithm`, ScrapeConfig relabel `action`) | Ignored or written out in Git (#122) |
| MLflow `OOMKilled` | 512Mi too small for MLflow 3.16 with two workers | 1Gi request / 2Gi limit (#123) |
| MinIO `ImagePullBackOff` | Upstream MinIO images are no longer publicly pullable | Argo artifacts moved to an S3 bucket via IRSA; MinIO removed (#123) |
| Local `kubectl` connection resets | Zscaler blocks the EKS API endpoint (a workstation issue, not a platform defect) | Zscaler off for the session (this runbook) |

The exit criterion for JDH-409 is one clean up-and-down cycle from empty
state with these fixes in place.

## Clean cycle, 2026-11-01

One deploy from empty state with #121, #122 and #123 on `main` (run
41337338974), dispatched at 18:34 and green at 19:07 UTC: 33 minutes. The
four live checks passed (baseline Synced and Healthy, no pod failures, event
bus pods up, MLflow 1/1), and a workflow wrote its output artifact to the S3
bucket through IRSA. The only unrequested node was the r6a.large for the Loki
chunks cache (JDH-418).

The first teardown attempt (19:11 UTC) failed. The SSO session had expired at
18:44; the AWS CLI kept working on role credentials it had cached earlier, but
Terraform's SDK could not refresh the token, so both `terraform destroy`
attempts failed on credentials. The script carried on regardless: its
Kubernetes phase had already removed the Kyverno policies, the webhooks and
the ArgoCD baseline Application, and its AWS phase ran against a live
platform. The cluster stayed up overnight until a fresh sign-in and a second
run (03:14 to 03:26 UTC on 2026-11-02) destroyed 189 resources and swept clean.
The re-sign-in step above and the script's preflight came out of this.

The JDH-409 exit criterion (one clean up-and-down cycle from empty state) is
met, with the teardown completing on its second run. The platform ran about 9
hours instead of 40 minutes.

Cost Explorer (unblended, read on 2026-11-13, still flagged as estimates by
AWS) for 2026-11-01 (the dry run, the clean cycle and the cluster left up
overnight) and 2026-11-02 (the teardown at 03:26). Daily totals are rounded
from the exact amounts; the "of which" lists omit lines under a cent:

| Day | Total | Of which |
|---|---|---|
| 2026-11-01 | 5.28 USD | EC2 other (NAT, EBS, IPv4) 1.56, EC2 compute 1.40, tax 1.21, EKS 0.71, RDS 0.27, KMS 0.08, VPC 0.04 |
| 2026-11-02 | 1.37 USD | EC2 compute 0.61, EKS 0.34, EC2 other 0.21, RDS 0.14, KMS 0.04, VPC 0.02 |
| 2026-11-03 to 2026-11-12 | 0.03 USD per day | KMS; the S3 state bucket and the DynamoDB lock table are below a cent together (2026-11-13 was a partial day when read) |

The two days come to 6.64 USD, 5.43 USD before tax, inside the 5 to 6.5 USD
estimated on the Linear issue (JDH-409) from about 11 cluster-hours at the
platform's on-demand rates. Every day after the teardown shows KMS and
sub-cent state storage only, which is the confirmation the Sweep section
asks for.
