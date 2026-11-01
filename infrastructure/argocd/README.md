# ArgoCD Applications

GitOps definitions for the platform's Kubernetes surface.

## What this closes

Terraform installs the ArgoCD **controller**, but a controller with no
`Application` resources manages nothing. This directory defines what ArgoCD
actually reconciles:

| Application | Path | Contents |
|-------------|------|----------|
| `platform-baseline` | `infrastructure/kubernetes/` | Kyverno governance (model-registry labels, image-signature verification), SLO rules, PodDisruptionBudgets, ResourceQuotas, progressive-delivery templates (Argo Rollouts analysis), Argo Events bus, monitoring rules, Grafana dashboards |

## Bootstrap

Terraform applies this Application (`modules/aws-platform/gitops-baseline.tf`)
right after ArgoCD and the CRD-providing charts, then blocks until ArgoCD
reports it Synced and Healthy; MLflow and MinIO are only installed after
that (the controllers that provide the baseline's CRDs necessarily come
first). There is no manual step. The Application tracks `main`, so a fresh
cluster syncs the current `main` baseline even when applying an older commit.
Tear down with `scripts/destroy-aws.sh`, which detaches the Application first;
a bare `terraform destroy` is not the supported path. ArgoCD is the only owner of `infrastructure/kubernetes/`
(ADR-017 decision 6): Terraform no longer applies the network policies or
dashboards itself.

From then on the platform surface is pulled from Git (`main`) with automated
sync, pruning, and self-heal. Verify with:

```bash
kubectl get application -n argocd
argocd app get platform-baseline   # if the CLI is configured
```

## Design notes

- **One Application, not app-of-apps.** A single environment (ADR-017) with a
  single synced path does not need the indirection.
- **`ServerSideApply=true`** because PrometheusRule and dashboard ConfigMaps
  exceed client-side-apply annotation size limits.
- **`CreateNamespace=false`** — namespaces are owned by Terraform; ArgoCD
  racing it caused ownership ambiguity in similar setups.
- **Bootstrap is deliberately manual.** Having Terraform apply this manifest
  would put a Git-reconciled object under Terraform state — two owners for
  one resource. One `kubectl apply` per cluster keeps the ownership boundary
  clean. If clusters multiply, promote to an ApplicationSet applied the same
  way.
