# Production Helm Values

Production-grade configurations with high availability for MLOps platform components.

## Overview

These values files configure critical platform services for production use with:
- Multi-replica deployments
- Pod anti-affinity for spread across nodes
- Persistent storage
- Resource requests and limits
- TLS/HTTPS enabled
- Metrics and monitoring integration

## Configuration Files

| File | Service | Replicas | Storage |
|------|---------|----------|---------|
| `argocd-values.yaml` | ArgoCD | 2 (server, controller, repo) | Redis HA |
| `prometheus-stack-values.yaml` | Prometheus/Grafana | 2/3 | 100Gi/10Gi |

## Key Differences from Dev

### ArgoCD
- 2 replicas for all components
- Redis HA with 3 HAProxy replicas
- Pod anti-affinity (hard requirement)
- TLS-only ingress
- RBAC configured

### Prometheus
- 2 Prometheus replicas with 30-day retention
- 3 Alertmanager replicas
- 100Gi persistent storage
- External labels for federation
- Alerting routes configured

### Grafana
- 2 replicas
- Persistent storage (10Gi)
- External Secrets for admin password
- TLS ingress

## Usage

### With Terraform

Reference these values in your Helm releases:

```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.9.0"
  namespace  = "argocd"

  values = [
    file("${path.module}/../../../helm/prod/argocd-values.yaml")
  ]
}
```

### Manual Installation

```bash
# ArgoCD
helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f infrastructure/helm/prod/argocd-values.yaml

# Prometheus Stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f infrastructure/helm/prod/prometheus-stack-values.yaml
```

## Pre-requisites

1. **ACM Certificates**: Create ACM certificates for your domains
2. **External Secrets**: Configure External Secrets Operator for Grafana admin password
3. **Storage Class**: Ensure `gp3` storage class is available
4. **DNS**: Configure DNS records for ingress domains

## Customization

### Update Domains

Replace placeholder domains:
```bash
# Update ArgoCD domain
sed -i 's/argocd.mlops.example.com/argocd.your-domain.com/g' argocd-values.yaml

# Update Grafana domain
sed -i 's/grafana.mlops.example.com/grafana.your-domain.com/g' prometheus-stack-values.yaml
```

### Configure Alerting

Update Alertmanager receivers in `prometheus-stack-values.yaml`:

```yaml
receivers:
  - name: 'critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/...'
        channel: '#alerts-critical'
    pagerduty_configs:
      - service_key: '<pagerduty-key>'
```

## Resource Requirements

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| ArgoCD Server (x2) | 500m | 512Mi | - |
| ArgoCD Controller (x2) | 1000m | 1Gi | - |
| Prometheus (x2) | 1000m | 4Gi | 100Gi |
| Alertmanager (x3) | 300m | 768Mi | 10Gi |
| Grafana (x2) | 500m | 1Gi | 10Gi |
| **Total Minimum** | ~7 CPU | ~16Gi | 220Gi |

## Monitoring

All components expose Prometheus metrics via ServiceMonitors:
- ArgoCD: Application sync status, repo server performance
- Prometheus: Self-monitoring, TSDB stats
- Grafana: Dashboard stats, data source health