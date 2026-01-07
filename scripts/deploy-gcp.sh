#!/bin/bash
set -euo pipefail

# MLOps Platform - GCP GKE Deployment
# Deploys platform with: Secret Manager secrets, External Secrets Operator,
# Workload Identity Federation for pod authentication, Node Auto-provisioning for autoscaling

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/gcp/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_GCP_REGION="europe-west4"
DEFAULT_GCP_ZONE="europe-west4-a"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   MLOps Platform - GCP GKE Deployment  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Features:${NC}"
echo "  - Auto-generated secrets stored in Secret Manager"
echo "  - External Secrets Operator for K8s sync"
echo "  - Workload Identity Federation for secure pod authentication"
echo "  - Node Auto-provisioning for dynamic GPU scaling"
echo ""

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

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud SDK is not installed"
        echo "  Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check gcloud auth
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not logged in to Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Get current project
    GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$GCP_PROJECT" ]]; then
        print_error "No GCP project set. Run 'gcloud config set project <PROJECT_ID>' first."
        exit 1
    fi
    print_status "Google Cloud SDK configured (Project: ${GCP_PROJECT})"

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Install with: brew install terraform"
        exit 1
    fi
    TF_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}')
    print_status "Terraform ${TF_VERSION} installed"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Install with: brew install kubectl"
        exit 1
    fi
    print_status "kubectl installed"

    # Check helm
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Install with: brew install helm"
        exit 1
    fi
    print_status "helm installed"

    # Check gke-gcloud-auth-plugin
    if ! gcloud components list --filter="id:gke-gcloud-auth-plugin" --format="value(state.name)" 2>/dev/null | grep -q "Installed"; then
        print_warning "gke-gcloud-auth-plugin may not be installed"
        print_info "Install with: gcloud components install gke-gcloud-auth-plugin"
    else
        print_status "gke-gcloud-auth-plugin installed"
    fi
}

# Setup terraform.tfvars
setup_tfvars() {
    print_info "Checking Terraform configuration..."

    # Get current project from gcloud
    GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

    if [[ -z "$GCP_PROJECT" ]]; then
        print_error "GCP_PROJECT is not set. Set with: export GCP_PROJECT=your-project-id"
        exit 1
    fi

    # Create tfvars if doesn't exist
    if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
        CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
        GCP_REGION=${GCP_REGION:-$DEFAULT_GCP_REGION}
        GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}

        cat > "${TF_DIR}/terraform.tfvars" <<EOF
# MLOps Platform - GCP Terraform Variables
# All secrets are AUTO-GENERATED and stored in Secret Manager
# No manual password configuration required!

project_id   = "${GCP_PROJECT}"
cluster_name = "${CLUSTER_NAME}"
region       = "${GCP_REGION}"
zones        = ["${GCP_ZONE}"]

labels = {
  environment = "dev"
  project     = "mlops-platform"
  managed_by  = "terraform"
}
EOF
        print_status "Created terraform.tfvars (project: ${GCP_PROJECT}, cluster: ${CLUSTER_NAME}, region: ${GCP_REGION})"
    else
        print_status "Using existing terraform.tfvars"
    fi
}

# Update backend configuration
update_backend() {
    print_info "Updating backend configuration..."

    GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}
    PROVIDERS_FILE="${TF_DIR}/providers.tf"

    if grep -q "YOUR_PROJECT_ID" "$PROVIDERS_FILE"; then
        sed -i.bak "s/YOUR_PROJECT_ID/${GCP_PROJECT}/g" "$PROVIDERS_FILE"
        rm -f "${PROVIDERS_FILE}.bak"
        print_status "Updated backend bucket name in providers.tf"
    fi
}

# Deploy infrastructure
deploy() {
    echo ""
    echo -e "${BLUE}Deploying GCP infrastructure...${NC}"
    print_warning "This will take approximately 15-25 minutes"
    echo ""

    cd "${TF_DIR}"

    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init -upgrade

    # Validate
    print_info "Validating Terraform configuration..."
    terraform validate

    # Plan
    print_info "Creating Terraform plan..."
    terraform plan -out=tfplan

    # Apply
    echo ""
    print_info "Applying Terraform configuration..."
    print_warning "Creating GKE cluster and all resources..."
    terraform apply tfplan

    # Clean up plan file
    rm -f tfplan

    # Configure kubectl
    configure_kubectl

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployment Complete!                   ${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Show access information
    terraform output -raw access_info 2>/dev/null || true
}

# Configure kubectl
configure_kubectl() {
    print_info "Configuring kubectl..."

    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
    GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --zone "$GCP_ZONE" \
        --project "$GCP_PROJECT"

    print_status "kubectl configured for cluster: ${CLUSTER_NAME}"
}

# Show status
status() {
    echo ""
    echo -e "${BLUE}Checking deployment status...${NC}"

    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
    GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

    # Configure kubectl if needed
    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --zone "$GCP_ZONE" \
        --project "$GCP_PROJECT" 2>/dev/null || true

    echo ""
    echo -e "${CYAN}Cluster Info:${NC}"
    gcloud container clusters describe "$CLUSTER_NAME" \
        --zone "$GCP_ZONE" \
        --project "$GCP_PROJECT" \
        --format="table(name,location,currentMasterVersion,status)" 2>/dev/null || print_warning "Cluster not found"

    echo ""
    echo -e "${CYAN}Nodes:${NC}"
    kubectl get nodes -o wide 2>/dev/null || print_warning "Cannot connect to cluster"

    echo ""
    echo -e "${CYAN}Core Pods:${NC}"
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | head -20 || true

    echo ""
    echo -e "${CYAN}Platform Services:${NC}"
    for ns in mlflow argocd argo monitoring kserve ingress-nginx external-secrets; do
        POD_COUNT=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        RUNNING=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$POD_COUNT" -gt 0 ]]; then
            echo "  $ns: $RUNNING/$POD_COUNT running"
        fi
    done
}

# Retrieve secrets
secrets() {
    echo ""
    echo -e "${BLUE}Retrieving secrets from Secret Manager...${NC}"

    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

    echo ""
    echo -e "${CYAN}MLflow Database Password:${NC}"
    gcloud secrets versions access latest \
        --secret="${CLUSTER_NAME}-mlflow-db-password" \
        --project="$GCP_PROJECT" 2>/dev/null || print_warning "Secret not found"

    echo ""
    echo -e "${CYAN}ArgoCD Admin Password:${NC}"
    gcloud secrets versions access latest \
        --secret="${CLUSTER_NAME}-argocd-admin-password" \
        --project="$GCP_PROJECT" 2>/dev/null || print_warning "Secret not found"

    echo ""
    echo -e "${CYAN}Grafana Admin Password:${NC}"
    gcloud secrets versions access latest \
        --secret="${CLUSTER_NAME}-grafana-admin-password" \
        --project="$GCP_PROJECT" 2>/dev/null || print_warning "Secret not found"

    echo ""
    echo -e "${CYAN}MinIO Root Password:${NC}"
    gcloud secrets versions access latest \
        --secret="${CLUSTER_NAME}-minio-root-password" \
        --project="$GCP_PROJECT" 2>/dev/null || print_warning "Secret not found"
    echo ""
}

# Show help
show_help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy   - Deploy the MLOps platform to GCP"
    echo "  status   - Check deployment status"
    echo "  secrets  - Retrieve stored secrets"
    echo "  destroy  - Destroy all resources (use destroy-gcp.sh instead)"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_PROJECT   - GCP project ID (default: from gcloud config)"
    echo "  CLUSTER_NAME  - Cluster name (default: mlops-platform-dev)"
    echo "  GCP_REGION    - GCP region (default: europe-west4)"
    echo "  GCP_ZONE      - GCP zone (default: europe-west4-a)"
    echo ""
    echo "Examples:"
    echo "  $0 deploy                           # Deploy with defaults"
    echo "  CLUSTER_NAME=prod $0 deploy         # Deploy with custom name"
    echo "  $0 status                           # Check status"
    echo "  $0 secrets                          # Get passwords"
}

# Main
case "${1:-help}" in
    deploy)
        check_prerequisites
        setup_tfvars
        update_backend
        deploy
        ;;
    status)
        status
        ;;
    secrets)
        secrets
        ;;
    destroy)
        print_warning "Use ./scripts/destroy-gcp.sh for safe destruction"
        exit 1
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
