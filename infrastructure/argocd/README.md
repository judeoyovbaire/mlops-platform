# ArgoCD Applications

GitOps definitions for the platform's Kubernetes surface.

## What this closes

Terraform installs the ArgoCD **controller**, but a controller with no
`Application` resources manages nothing. This directory defines what ArgoCD
actually reconciles:

| Application | Path | Contents |
|-------------|------|----------|
| `platform-baseline` | `infrastructure/kubernetes/` | Kyverno governance (model-registry labels, image-signature verification), SLO rules, PodDisruptionBudgets, ResourceQuotas, VPA, progressive-delivery templates (Argo Rollouts analysis), Argo Events bus, monitoring rules, Grafana dashboards |

## Bootstrap (once per cluster)

After `terraform apply` has installed ArgoCD:

```bash
kubectl apply -f infrastructure/argocd/platform-baseline.yaml
```

From then on the platform surface is pulled from Git (`main`) with automated
sync, pruning, and self-heal. Verify with:

```bash
kubectl get application -n argocd
argocd app get platform-baseline   # if the CLI is configured
```

## Design notes

- **One Application, not app-of-apps (yet).** A single environment with a
  single synced path does not need the indirection; an ApplicationSet per
  environment is the natural next step when prod diverges from dev.
- **`ServerSideApply=true`** because PrometheusRule and dashboard ConfigMaps
  exceed client-side-apply annotation size limits.
- **`CreateNamespace=false`** — namespaces are owned by Terraform; ArgoCD
  racing it caused ownership ambiguity in similar setups.
- **Bootstrap is deliberately manual.** Having Terraform apply this manifest
  would put a Git-reconciled object under Terraform state — two owners for
  one resource. One `kubectl apply` per cluster keeps the ownership boundary
  clean. If clusters multiply, promote to an ApplicationSet applied the same
  way.
