#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${GREEN}MLOps Platform Installation Script${NC}"
echo "========================================"

# Check prerequisites
log_info "Checking prerequisites..."

command -v kubectl &> /dev/null || { log_error "kubectl not found. Please install kubectl first."; exit 1; }
command -v helm &> /dev/null || { log_error "helm not found. Please install helm first."; exit 1; }

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

log_info "Prerequisites OK"

# Create namespaces
log_info "Creating namespaces..."
kubectl apply -f "${PROJECT_ROOT}/infrastructure/kubernetes/namespace.yaml"

# Add Helm repositories
log_info "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo add mlflow https://community-charts.github.io/helm-charts || true
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

# Install MLflow
log_info "Installing MLflow..."
if ! helm upgrade --install mlflow mlflow/mlflow \
    --namespace mlflow \
    --values "${PROJECT_ROOT}/infrastructure/helm/mlflow-values.yaml" \
    --timeout 5m \
    --wait; then
    log_error "Failed to install MLflow"
    exit 1
fi

# Install KServe
log_info "Installing KServe..."
# Install cert-manager (KServe dependency)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml || true
log_info "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager || true
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager || true

# Install KServe
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml || {
    log_warn "KServe CRDs may already exist, continuing..."
}
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve-cluster-resources.yaml || {
    log_warn "KServe cluster resources may already exist, continuing..."
}

# Wait for KServe controller
log_info "Waiting for KServe controller to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/kserve-controller-manager -n kserve || {
    log_warn "KServe controller not ready yet, it may need more time"
}

# Install ArgoCD
log_info "Installing ArgoCD..."
if ! helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --values "${PROJECT_ROOT}/infrastructure/helm/argocd-values.yaml" \
    --timeout 5m \
    --wait; then
    log_error "Failed to install ArgoCD"
    exit 1
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "\nAccess the services:"
echo -e "  MLflow:  kubectl port-forward svc/mlflow 5000:5000 -n mlflow"
echo -e "  ArgoCD:  kubectl port-forward svc/argocd-server 8080:443 -n argocd"
echo -e "\nArgoCD initial admin password:"
echo -e "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo -e "\nKServe InferenceService example:"
echo -e "  kubectl apply -f ${PROJECT_ROOT}/components/kserve/inferenceservice-examples.yaml"