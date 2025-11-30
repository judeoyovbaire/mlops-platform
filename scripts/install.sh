#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}MLOps Platform Installation Script${NC}"
echo "========================================"

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install helm first.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites OK${NC}"

# Create namespaces
echo -e "\n${YELLOW}Creating namespaces...${NC}"
kubectl apply -f infrastructure/kubernetes/namespace.yaml

# Add Helm repositories
echo -e "\n${YELLOW}Adding Helm repositories...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add mlflow https://community-charts.github.io/helm-charts
helm repo add seldon https://storage.googleapis.com/seldon-charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install MLflow
echo -e "\n${YELLOW}Installing MLflow...${NC}"
helm upgrade --install mlflow mlflow/mlflow \
    --namespace mlflow \
    --values infrastructure/helm/mlflow-values.yaml \
    --wait

# Install Seldon Core
echo -e "\n${YELLOW}Installing Seldon Core...${NC}"
helm upgrade --install seldon-core seldon/seldon-core-operator \
    --namespace seldon-system \
    --set usageMetrics.enabled=true \
    --set istio.enabled=true \
    --wait

# Install ArgoCD
echo -e "\n${YELLOW}Installing ArgoCD...${NC}"
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --values infrastructure/helm/argocd-values.yaml \
    --wait

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "\nAccess the services:"
echo -e "  MLflow:  kubectl port-forward svc/mlflow 5000:5000 -n mlflow"
echo -e "  ArgoCD:  kubectl port-forward svc/argocd-server 8080:443 -n argocd"
echo -e "\nArgoCD initial admin password:"
echo -e "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
