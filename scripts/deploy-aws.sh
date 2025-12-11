#!/bin/bash
set -e

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
TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_AWS_REGION="eu-west-1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MLOps Platform - AWS EKS Deployment  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Features:${NC}"
echo "  • Auto-generated secrets stored in AWS SSM"
echo "  • External Secrets Operator for K8s sync"
echo "  • No manual password configuration required"
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

    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        echo "  Install with: brew install awscli"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}
    print_status "AWS CLI configured (Account: ${AWS_ACCOUNT_ID}, Region: ${AWS_REGION})"

    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Install with: brew install terraform"
        exit 1
    fi
    TF_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}')
    print_status "Terraform ${TF_VERSION} installed"

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Install with: brew install kubectl"
        exit 1
    fi
    print_status "kubectl installed"

    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Install with: brew install helm"
        exit 1
    fi
    print_status "helm installed"
}

# Setup terraform.tfvars (now optional - just for overrides)
setup_tfvars() {
    print_info "Checking Terraform configuration..."

    # Create minimal tfvars if user wants custom values
    if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
        # Use environment variables or defaults
        CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
        AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}

        cat > "${TF_DIR}/terraform.tfvars" <<EOF
# MLOps Platform - Terraform Variables
# All secrets are AUTO-GENERATED and stored in AWS SSM Parameter Store
# No manual password configuration required!

cluster_name = "${CLUSTER_NAME}"
aws_region   = "${AWS_REGION}"

tags = {
  Environment = "dev"
  Project     = "mlops-platform"
  ManagedBy   = "terraform"
}
EOF
        print_status "Created terraform.tfvars (cluster: ${CLUSTER_NAME}, region: ${AWS_REGION})"
    else
        print_status "Using existing terraform.tfvars"
    fi
}

# Deploy infrastructure
deploy() {
    echo ""
    echo -e "${BLUE}Deploying AWS infrastructure...${NC}"
    print_warning "This will take approximately 15-20 minutes"
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
    AWS_REGION=$(terraform output -raw configure_kubectl | grep -oP '(?<=--region )\S+')
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

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
    print_info "Cluster: ${CLUSTER_NAME}"

    # Update kubeconfig
    AWS_REGION=$(terraform output -raw configure_kubectl | grep -oE '\-\-region [a-z0-9-]+' | awk '{print $2}')
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" 2>/dev/null

    echo ""
    echo -e "${BLUE}Nodes:${NC}"
    kubectl get nodes 2>/dev/null || print_error "Cannot connect to cluster"

    echo ""
    echo -e "${BLUE}Pods (summary):${NC}"
    kubectl get pods -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn || true

    echo ""
    echo -e "${BLUE}External Secrets Status:${NC}"
    kubectl get externalsecrets -A 2>/dev/null || print_warning "External Secrets not ready yet"

    echo ""
    echo -e "${BLUE}Ingresses (ALB URLs):${NC}"
    kubectl get ingress -A 2>/dev/null || true

    echo ""
    echo -e "${BLUE}SSM Secrets (stored securely):${NC}"
    echo "  /${CLUSTER_NAME}/mlflow/db-password"
    echo "  /${CLUSTER_NAME}/kubeflow/db-password"
    echo "  /${CLUSTER_NAME}/minio/root-password"
    echo "  /${CLUSTER_NAME}/argocd/admin-password"
    echo ""
    echo "  Retrieve with: aws ssm get-parameter --name \"/<param>\" --with-decryption"
}

# Show secrets from SSM
secrets() {
    echo ""
    echo -e "${BLUE}Retrieving secrets from AWS SSM Parameter Store...${NC}"

    cd "${TF_DIR}"

    if ! terraform output cluster_name &> /dev/null; then
        print_error "No deployment found"
        exit 1
    fi

    CLUSTER_NAME=$(terraform output -raw cluster_name)
    AWS_REGION=$(terraform output -raw configure_kubectl | grep -oE '\-\-region [a-z0-9-]+' | awk '{print $2}')

    echo ""
    echo -e "${CYAN}MLflow DB Password:${NC}"
    aws ssm get-parameter --name "/${CLUSTER_NAME}/mlflow/db-password" --with-decryption --query 'Parameter.Value' --output text --region "${AWS_REGION}" 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}Kubeflow Pipeline DB Password:${NC}"
    aws ssm get-parameter --name "/${CLUSTER_NAME}/kubeflow/db-password" --with-decryption --query 'Parameter.Value' --output text --region "${AWS_REGION}" 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}MinIO Root Password:${NC}"
    aws ssm get-parameter --name "/${CLUSTER_NAME}/minio/root-password" --with-decryption --query 'Parameter.Value' --output text --region "${AWS_REGION}" 2>/dev/null || print_error "Not found"

    echo ""
    echo -e "${CYAN}ArgoCD Admin Password:${NC}"
    aws ssm get-parameter --name "/${CLUSTER_NAME}/argocd/admin-password" --with-decryption --query 'Parameter.Value' --output text --region "${AWS_REGION}" 2>/dev/null || print_error "Not found"

    echo ""
}

# Destroy infrastructure
destroy() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  WARNING: Destroying AWS Infrastructure${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    print_warning "This will delete ALL resources including:"
    echo "  - EKS cluster and all workloads"
    echo "  - RDS database (data will be lost)"
    echo "  - S3 bucket and artifacts"
    echo "  - VPC and networking"
    echo ""

    read -p "Are you sure you want to destroy? (yes/no): " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        print_info "Destroy cancelled"
        exit 0
    fi

    cd "${TF_DIR}"

    print_info "Destroying infrastructure..."
    terraform destroy -auto-approve

    print_status "Infrastructure destroyed"
    print_info "Run 'kubectl config delete-context' to clean up local kubeconfig if needed"
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
            destroy
            ;;
        --help|help)
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  deploy   Deploy MLOps platform to AWS EKS (fully automated)"
            echo "  status   Check deployment status"
            echo "  secrets  Retrieve secrets from AWS SSM Parameter Store"
            echo "  destroy  Destroy all AWS resources"
            echo "  help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  CLUSTER_NAME  Override cluster name (default: mlops-platform-dev)"
            echo "  AWS_REGION    Override AWS region (default: eu-west-1)"
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
