#!/bin/bash
# Local MLOps Platform Deployment Script
# Deploys the MLOps stack to a local Kind cluster

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOCAL_DIR="$ROOT_DIR/infrastructure/local"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    local deps=("kind" "kubectl" "helm")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "$dep is required but not installed"
            exit 1
        fi
    done
    log_info "All dependencies found"
}

deploy() {
    check_dependencies

    log_info "Creating Kind cluster..."
    if kind get clusters | grep -q "mlops-local"; then
        log_warn "Cluster 'mlops-local' already exists"
    else
        kind create cluster --config "$LOCAL_DIR/kind-config.yaml" --wait 120s
    fi

    log_info "Setting kubectl context..."
    kubectl cluster-info --context kind-mlops-local

    log_info "Adding Helm repositories..."
    helm repo add argo https://argoproj.github.io/argo-helm || true
    helm repo add minio https://charts.min.io/ || true
    helm repo add mlflow https://community-charts.github.io/helm-charts || true
    helm repo update

    log_info "Creating namespaces..."
    kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace mlflow --dry-run=client -o yaml | kubectl apply -f -

    log_info "Deploying PostgreSQL for MLflow..."
    kubectl apply -f "$LOCAL_DIR/manifests/postgres-local.yaml"
    kubectl wait --for=condition=available deployment/postgres-mlflow -n mlflow --timeout=120s

    log_info "Deploying MinIO..."
    # Create MinIO credentials secret for Argo
    kubectl create secret generic minio-creds -n argo \
        --from-literal=accesskey=minio \
        --from-literal=secretkey=minio123 \
        --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install minio minio/minio \
        -n argo \
        -f "$LOCAL_DIR/values/minio-values-local.yaml" \
        --wait --timeout 5m

    log_info "Deploying Argo Workflows..."
    helm upgrade --install argo-workflows argo/argo-workflows \
        -n argo \
        -f "$LOCAL_DIR/values/argo-workflows-values-local.yaml" \
        --wait --timeout 5m

    log_info "Deploying ArgoCD..."
    helm upgrade --install argocd argo/argo-cd \
        -n argocd \
        -f "$LOCAL_DIR/values/argocd-values-local.yaml" \
        --wait --timeout 5m

    log_info "Deploying MLflow..."
    helm upgrade --install mlflow mlflow/mlflow \
        -n mlflow \
        -f "$LOCAL_DIR/values/mlflow-values-local.yaml" \
        --wait --timeout 5m

    log_info ""
    log_info "=========================================="
    log_info "Local MLOps Platform Deployed Successfully!"
    log_info "=========================================="
    log_info ""
    log_info "Access URLs:"
    log_info "  MLflow:         http://localhost:5000"
    log_info "  ArgoCD:         http://localhost:8080"
    log_info "  Argo Workflows: http://localhost:2746"
    log_info "  MinIO Console:  http://localhost:9001"
    log_info ""
    log_info "Credentials:"
    log_info "  ArgoCD:  admin / admin"
    log_info "  MinIO:   minio / minio123"
    log_info ""
    log_info "Run 'make status-local' to check pod status"
}

destroy() {
    log_info "Destroying Kind cluster..."
    kind delete cluster --name mlops-local
    log_info "Local cluster destroyed"
}

status() {
    log_info "Checking pod status..."
    echo ""
    echo "=== ArgoCD ==="
    kubectl get pods -n argocd 2>/dev/null || echo "Namespace not found"
    echo ""
    echo "=== Argo Workflows ==="
    kubectl get pods -n argo 2>/dev/null || echo "Namespace not found"
    echo ""
    echo "=== MLflow ==="
    kubectl get pods -n mlflow 2>/dev/null || echo "Namespace not found"
    echo ""
    echo "=== Services ==="
    kubectl get svc -A | grep -E "NodePort|LoadBalancer" 2>/dev/null || echo "No external services found"
}

usage() {
    echo "Usage: $0 {deploy|destroy|status}"
    echo ""
    echo "Commands:"
    echo "  deploy   - Create local Kind cluster and deploy MLOps stack"
    echo "  destroy  - Delete local Kind cluster"
    echo "  status   - Show pod status for all components"
    exit 1
}

case "${1:-}" in
    deploy)
        deploy
        ;;
    destroy)
        destroy
        ;;
    status)
        status
        ;;
    *)
        usage
        ;;
esac