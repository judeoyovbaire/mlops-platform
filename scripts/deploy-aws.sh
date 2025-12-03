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
TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/dev"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MLOps Platform - AWS EKS Deployment  ${NC}"
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

    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    print_status "AWS CLI configured"

    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Install with: brew install terraform"
        exit 1
    fi
    print_status "Terraform is installed"

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
}

# Check for tfvars file
check_tfvars() {
    if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
        print_warning "terraform.tfvars not found"
        print_info "Creating from example..."

        if [[ -f "${TF_DIR}/terraform.tfvars.example" ]]; then
            cp "${TF_DIR}/terraform.tfvars.example" "${TF_DIR}/terraform.tfvars"
            print_info "Please edit ${TF_DIR}/terraform.tfvars with your values"
            print_info "At minimum, set mlflow_db_password to a secure value"
            exit 1
        else
            # Create a basic tfvars file
            cat > "${TF_DIR}/terraform.tfvars" <<EOF
# MLOps Platform - Terraform Variables
cluster_name       = "mlops-platform-dev"
aws_region         = "us-west-2"
mlflow_db_password = "$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)"

tags = {
  Environment = "dev"
  Project     = "mlops-platform"
}
EOF
            print_status "Created terraform.tfvars with generated password"
        fi
    fi
    print_status "terraform.tfvars exists"
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
    AWS_REGION=$(terraform output -raw configure_kubectl | grep -oP '(?<=--region )\S+')
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" 2>/dev/null

    echo ""
    echo -e "${BLUE}Nodes:${NC}"
    kubectl get nodes 2>/dev/null || print_error "Cannot connect to cluster"

    echo ""
    echo -e "${BLUE}Pods:${NC}"
    kubectl get pods -A 2>/dev/null | head -30

    echo ""
    echo -e "${BLUE}Ingresses (ALB URLs):${NC}"
    kubectl get ingress -A 2>/dev/null

    echo ""
    echo -e "${BLUE}ArgoCD Password:${NC}"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo "" || print_warning "ArgoCD not ready yet"
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
            check_tfvars
            deploy
            print_access_info
            ;;
        status)
            status
            ;;
        destroy)
            destroy
            ;;
        --help|help)
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  deploy   Deploy MLOps platform to AWS EKS"
            echo "  status   Check deployment status"
            echo "  destroy  Destroy all AWS resources"
            echo "  help     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 deploy   # Deploy to AWS"
            echo "  $0 status   # Check status"
            echo "  $0 destroy  # Tear down everything"
            exit 0
            ;;
        *)
            echo "Usage: $0 {deploy|status|destroy|help}"
            exit 1
            ;;
    esac
}

main "$@"
