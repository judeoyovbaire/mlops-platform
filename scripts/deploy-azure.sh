#!/bin/bash
set -euo pipefail

# MLOps Platform - Azure AKS Deployment
# Deploys platform with: Azure Key Vault secrets, External Secrets Operator,
# Workload Identity for pod authentication, KEDA for autoscaling

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
TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/azure/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_AZURE_LOCATION="westeurope"
DEFAULT_RESOURCE_GROUP="rg-mlops-platform-dev"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MLOps Platform - Azure AKS Deployment ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Features:${NC}"
echo "  - Auto-generated secrets stored in Azure Key Vault"
echo "  - External Secrets Operator for K8s sync"
echo "  - Workload Identity for secure pod authentication"
echo "  - KEDA for event-driven autoscaling"
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

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        echo "  Install with: brew install azure-cli"
        exit 1
    fi

    # Check Azure login
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi

    AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    AZURE_SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_status "Azure CLI configured (Subscription: ${AZURE_SUBSCRIPTION_NAME})"

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

    # Check kubelogin (required for AKS authentication)
    if ! command -v kubelogin &> /dev/null; then
        print_warning "kubelogin is not installed. Install with: brew install Azure/kubelogin/kubelogin"
        print_info "kubelogin is required for AKS cluster authentication"
    else
        print_status "kubelogin installed"
    fi
}

# Setup terraform.tfvars
setup_tfvars() {
    print_info "Checking Terraform configuration..."

    # Create minimal tfvars if user wants custom values
    if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
        # Use environment variables or defaults
        CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
        AZURE_LOCATION=${AZURE_LOCATION:-$DEFAULT_AZURE_LOCATION}
        RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}

        cat > "${TF_DIR}/terraform.tfvars" <<EOF
# MLOps Platform - Azure Terraform Variables
# All secrets are AUTO-GENERATED and stored in Azure Key Vault
# No manual password configuration required!

cluster_name   = "${CLUSTER_NAME}"
azure_location = "${AZURE_LOCATION}"

tags = {
  Environment = "dev"
  Project     = "mlops-platform"
  ManagedBy   = "terraform"
}
EOF
        print_status "Created terraform.tfvars (cluster: ${CLUSTER_NAME}, location: ${AZURE_LOCATION})"
    else
        print_status "Using existing terraform.tfvars"
    fi
}

# Deploy infrastructure
deploy() {
    echo ""
    echo -e "${BLUE}Deploying Azure infrastructure...${NC}"
    print_warning "This will take approximately 15-25 minutes"
    echo ""

    cd "${TF_DIR}"

    # Initialize Terraform
    print_info "Initializing Terraform..."
    terraform init -upgrade

    # Plan
    print_info "Planning deployment..."
    terraform plan -out=tfplan

    # Apply
    print_info "Applying deployment..."
    terraform apply tfplan

    # Configure kubectl
    print_info "Configuring kubectl..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name)

    # Get AKS credentials
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --overwrite-existing

    # Convert kubeconfig to use kubelogin
    if command -v kubelogin &> /dev/null; then
        kubelogin convert-kubeconfig -l azurecli
        print_status "Configured kubelogin for Azure AD authentication"
    fi

    print_status "Deployment complete!"
}

# Show status
status() {
    echo ""
    echo -e "${BLUE}Checking deployment status...${NC}"

    cd "${TF_DIR}"

    # Check if cluster exists
    if ! terraform output cluster_name &> /dev/null; then
        print_error "No deployment found"
        exit 1
    fi

    CLUSTER_NAME=$(terraform output -raw cluster_name)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name)
    print_info "Cluster: ${CLUSTER_NAME}"
    print_info "Resource Group: ${RESOURCE_GROUP}"

    # Update kubeconfig
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --overwrite-existing 2>/dev/null

    if command -v kubelogin &> /dev/null; then
        kubelogin convert-kubeconfig -l azurecli 2>/dev/null || true
    fi

    echo ""
    echo -e "${BLUE}Nodes:${NC}"
    kubectl get nodes 2>/dev/null || print_error "Cannot connect to cluster"

    echo ""
    echo -e "${BLUE}Node Pools:${NC}"
    az aks nodepool list \
        --resource-group "${RESOURCE_GROUP}" \
        --cluster-name "${CLUSTER_NAME}" \
        --output table 2>/dev/null || true

    echo ""
    echo -e "${BLUE}Pods (summary):${NC}"
    kubectl get pods -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn || true

    echo ""
    echo -e "${BLUE}External Secrets Status:${NC}"
    kubectl get externalsecrets -A 2>/dev/null || print_warning "External Secrets not ready yet"

    echo ""
    echo -e "${BLUE}KEDA Status:${NC}"
    kubectl get scaledobjects -A 2>/dev/null || print_warning "KEDA ScaledObjects not configured yet"

    echo ""
    echo -e "${BLUE}Ingresses:${NC}"
    kubectl get ingress -A 2>/dev/null || true

    echo ""
    echo -e "${BLUE}Key Vault Secrets (stored securely):${NC}"
    KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "unknown")
    echo "  Key Vault: ${KEY_VAULT_NAME}"
    echo "  - mlflow-db-password"
    echo "  - minio-root-password"
    echo "  - argocd-admin-password"
    echo "  - grafana-admin-password"
    echo ""
    echo "  Retrieve with: az keyvault secret show --vault-name ${KEY_VAULT_NAME} --name <secret-name>"
}

# Show secrets from Key Vault
secrets() {
    echo ""
    echo -e "${BLUE}Retrieving secrets from Azure Key Vault...${NC}"

    cd "${TF_DIR}"

    if ! terraform output cluster_name &> /dev/null; then
        print_error "No deployment found"
        exit 1
    fi

    KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)

    if [[ -z "$KEY_VAULT_NAME" ]]; then
        print_error "Could not determine Key Vault name"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}MLflow DB Password:${NC}"
    az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "mlflow-db-password" --query 'value' -o tsv 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}MinIO Root Password:${NC}"
    az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "minio-root-password" --query 'value' -o tsv 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}ArgoCD Admin Password:${NC}"
    az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "argocd-admin-password" --query 'value' -o tsv 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}Grafana Admin Password:${NC}"
    az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "grafana-admin-password" --query 'value' -o tsv 2>/dev/null || print_error "Not found"

    echo ""
}

# Destroy infrastructure - delegates to destroy-azure.sh
destroy() {
    # Use the dedicated destroy script which handles cleanup properly
    "${SCRIPT_DIR}/destroy-azure.sh" "$@"
}

# Print access information
print_access_info() {
    cd "${TF_DIR}"
    terraform output access_info 2>/dev/null || true
}

# Main execution
main() {
    case "${1:-}" in
        deploy)
            check_prerequisites
            setup_tfvars
            deploy
            print_access_info
            ;;
        status)
            status
            ;;
        secrets)
            secrets
            ;;
        destroy)
            shift  # Remove 'destroy' from arguments
            destroy "$@"
            ;;
        --help|help)
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  deploy   Deploy MLOps platform to Azure AKS (fully automated)"
            echo "  status   Check deployment status"
            echo "  secrets  Retrieve secrets from Azure Key Vault"
            echo "  destroy  Destroy all Azure resources"
            echo "  help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  CLUSTER_NAME     Override cluster name (default: mlops-platform-dev)"
            echo "  AZURE_LOCATION   Override Azure location (default: westeurope)"
            echo "  RESOURCE_GROUP   Override resource group name (default: rg-mlops-platform-dev)"
            echo ""
            echo "Examples:"
            echo "  $0 deploy                              # Deploy with defaults"
            echo "  CLUSTER_NAME=prod $0 deploy            # Deploy with custom name"
            echo "  $0 status                              # Check deployment status"
            echo "  $0 secrets                             # Show all passwords"
            echo "  $0 destroy                             # Tear down everything"
            exit 0
            ;;
        *)
            echo "Usage: $0 {deploy|status|secrets|destroy|help}"
            exit 1
            ;;
    esac
}

main "$@"
