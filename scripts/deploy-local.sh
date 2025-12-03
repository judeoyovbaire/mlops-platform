#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="mlops-platform"

# Manifest paths
LOCAL_MANIFESTS="${PROJECT_ROOT}/infrastructure/kubernetes/local"
KIND_CONFIG="${PROJECT_ROOT}/infrastructure/kind/cluster-config.yaml"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MLOps Platform - Local Deployment    ${NC}"
echo -e "${BLUE}========================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo ""
    echo -e "${BLUE}Checking prerequisites...${NC}"

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    print_status "Docker is running"

    if ! command -v kind &> /dev/null; then
        print_error "kind is not installed. Install with: brew install kind"
        exit 1
    fi
    print_status "kind is installed"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Install with: brew install kubectl"
        exit 1
    fi
    print_status "kubectl is installed"

    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Install with: brew install helm"
        exit 1
    fi
    print_status "helm is installed"

    # Verify manifest files exist
    if [[ ! -f "${LOCAL_MANIFESTS}/namespaces.yaml" ]]; then
        print_error "Local manifests not found at ${LOCAL_MANIFESTS}"
        exit 1
    fi
    print_status "Local manifests found"
}

# Create kind cluster
create_cluster() {
    echo ""
    echo -e "${BLUE}Setting up Kind cluster...${NC}"

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        print_warning "Cluster '${CLUSTER_NAME}' already exists"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deleting existing cluster..."
            kind delete cluster --name "${CLUSTER_NAME}"
        else
            print_info "Using existing cluster"
            kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null || {
                print_error "Cannot connect to existing cluster"
                exit 1
            }
            return 0
        fi
    fi

    print_info "Creating kind cluster '${CLUSTER_NAME}'..."
    kind create cluster --config "${KIND_CONFIG}"

    # Wait for cluster to be ready
    print_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    print_status "Kind cluster created successfully"
}

# Create namespaces from manifest
create_namespaces() {
    echo ""
    echo -e "${BLUE}Creating namespaces...${NC}"

    kubectl apply -f "${LOCAL_MANIFESTS}/namespaces.yaml"

    print_status "Namespaces created"
}

# Install MLflow from manifest
install_mlflow() {
    echo ""
    echo -e "${BLUE}Installing MLflow (local mode)...${NC}"

    kubectl apply -f "${LOCAL_MANIFESTS}/mlflow.yaml"

    print_info "Waiting for MLflow to be ready..."
    kubectl rollout status deployment/mlflow -n mlflow --timeout=180s

    print_status "MLflow installed (accessible at http://localhost:5050)"
}

# Install ArgoCD from official manifests
install_argocd() {
    echo ""
    echo -e "${BLUE}Installing ArgoCD...${NC}"

    # Install ArgoCD using official manifests
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    print_info "Waiting for ArgoCD to be ready..."
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

    # Patch service to NodePort for local access
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "targetPort": 8080, "nodePort": 30800}]}}'

    # Get initial admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    print_status "ArgoCD installed (accessible at https://localhost:8080)"
    print_info "ArgoCD credentials - username: admin, password: ${ARGOCD_PASSWORD}"
}

# Install KServe
install_kserve() {
    echo ""
    echo -e "${BLUE}Installing KServe...${NC}"

    # Install cert-manager (required by KServe)
    print_info "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

    print_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=180s

    # Install KServe using server-side apply to handle large CRDs
    print_info "Installing KServe CRDs and controller..."
    kubectl apply --server-side --force-conflicts -f https://github.com/kserve/kserve/releases/download/v0.14.1/kserve.yaml

    print_info "Waiting for KServe to be ready..."
    sleep 10  # Give time for CRDs to register
    kubectl wait --for=condition=Available deployment --all -n kserve --timeout=300s || true

    # Wait for webhook to be ready before installing cluster resources
    print_info "Waiting for KServe webhook to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.14.1/kserve-cluster-resources.yaml 2>/dev/null; then
            print_status "KServe cluster resources installed"
            break
        fi
        if [[ $attempt -eq $max_attempts ]]; then
            print_error "Failed to install KServe cluster resources after ${max_attempts} attempts"
            return 1
        fi
        print_info "Webhook not ready, retrying in 10s... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done

    # Configure KServe for RawDeployment mode using manifest-based config
    print_info "Configuring KServe for RawDeployment mode (no Knative)..."
    kubectl patch configmap inferenceservice-config -n kserve --type merge \
        -p "$(cat ${LOCAL_MANIFESTS}/kserve-config.yaml | grep -A10 'data:' | tail -n +2 | sed 's/^/  /' | sed '1s/^/{\"data\": {/' | sed 's/deploy: |/\"deploy\": \"/' | sed 's/$/\"}}/;s/    {/  {/g' | tr -d '\n' | sed 's/  \"/\"/g' | sed 's/}  }/}}/g')" 2>/dev/null || \
        kubectl patch configmap inferenceservice-config -n kserve --type merge \
        -p '{"data":{"deploy":"{\"defaultDeploymentMode\": \"RawDeployment\"}"}}'

    # Restart KServe controller to pick up config changes
    kubectl rollout restart deployment kserve-controller-manager -n kserve
    kubectl rollout status deployment kserve-controller-manager -n kserve --timeout=60s

    print_status "KServe installed (RawDeployment mode)"
}

# Apply platform manifests
apply_manifests() {
    echo ""
    echo -e "${BLUE}Applying platform manifests...${NC}"

    # Apply network policies
    kubectl apply -f "${PROJECT_ROOT}/infrastructure/kubernetes/network-policies.yaml" || true

    print_status "Platform manifests applied"
}

# Deploy example model from manifest
deploy_example() {
    echo ""
    echo -e "${BLUE}Deploying example inference service...${NC}"

    # Wait for KServe webhook to be fully ready
    print_info "Waiting for KServe webhook to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if kubectl apply -f "${LOCAL_MANIFESTS}/inferenceservice-example.yaml" 2>/dev/null; then
            print_status "InferenceService manifest applied"
            break
        fi
        if [[ $attempt -eq $max_attempts ]]; then
            print_error "Failed to deploy InferenceService after ${max_attempts} attempts"
            print_info "You can deploy later with: kubectl apply -f ${LOCAL_MANIFESTS}/inferenceservice-example.yaml"
            return 1
        fi
        print_info "Webhook not ready, retrying in 10s... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done

    print_info "Waiting for InferenceService to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=Ready inferenceservice/sklearn-iris -n mlops --timeout=300s || {
        print_warning "InferenceService not ready yet. Check status with: kubectl get inferenceservice -n mlops"
        return 1
    }

    print_status "Example InferenceService deployed and ready"
}

# Print access information
print_access_info() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Deployment Complete!                  ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}Access URLs:${NC}"
    echo -e "  MLflow:  ${GREEN}http://localhost:5050${NC}"
    echo -e "  ArgoCD:  ${GREEN}https://localhost:8080${NC} (accept self-signed cert)"
    echo ""
    echo -e "${BLUE}ArgoCD Credentials:${NC}"
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD}${NC}"
    echo ""
    echo -e "${BLUE}Test Inference:${NC}"
    echo "  kubectl port-forward svc/sklearn-iris-predictor -n mlops 8082:80"
    echo "  curl -X POST http://localhost:8082/v1/models/sklearn-iris:predict \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"instances\": [[5.1, 3.5, 1.4, 0.2]]}'"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  kubectl get pods -A                    # View all pods"
    echo "  kubectl get inferenceservice -n mlops # View KServe models"
    echo "  make local-cleanup                    # Delete cluster"
    echo ""
    echo -e "${BLUE}Manifests used:${NC}"
    echo "  ${LOCAL_MANIFESTS}/namespaces.yaml"
    echo "  ${LOCAL_MANIFESTS}/mlflow.yaml"
    echo "  ${LOCAL_MANIFESTS}/kserve-config.yaml"
    echo "  ${LOCAL_MANIFESTS}/inferenceservice-example.yaml"
    echo ""
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${BLUE}Cleaning up local deployment...${NC}"
    kind delete cluster --name "${CLUSTER_NAME}"
    print_status "Cluster deleted"
}

# Main execution
main() {
    case "${1:-}" in
        --cleanup|cleanup)
            cleanup
            exit 0
            ;;
        --help|help)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  (none)    Deploy MLOps platform locally"
            echo "  cleanup   Delete the kind cluster"
            echo "  help      Show this help message"
            echo ""
            echo "All resources are deployed from manifest files in:"
            echo "  ${LOCAL_MANIFESTS}/"
            exit 0
            ;;
    esac

    check_prerequisites
    create_cluster
    create_namespaces
    install_mlflow
    install_argocd
    install_kserve
    apply_manifests
    deploy_example
    print_access_info
}

main "$@"