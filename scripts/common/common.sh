#!/bin/bash
# =============================================================================
# Common functions and variables for MLOps Platform scripts
# =============================================================================
# Source this file in other scripts: source "$(dirname "$0")/lib/common.sh"

# Prevent multiple sourcing
if [[ -n "${_MLOPS_COMMON_LOADED:-}" ]]; then
    return 0
fi
_MLOPS_COMMON_LOADED=1

# =============================================================================
# Colors
# =============================================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================
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

print_header() {
    local title="$1"
    local color="${2:-$BLUE}"
    echo ""
    echo -e "${color}========================================${NC}"
    echo -e "${color}  $title${NC}"
    echo -e "${color}========================================${NC}"
    echo ""
}

# =============================================================================
# Prerequisite Checks
# =============================================================================
check_command() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &> /dev/null; then
        print_error "$cmd is not installed"
        if [[ -n "$install_hint" ]]; then
            echo "  Install with: $install_hint"
        fi
        return 1
    fi
    return 0
}

check_common_prerequisites() {
    print_info "Checking common prerequisites..."

    check_command "terraform" "brew install terraform" || exit 1
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}')
    print_status "Terraform ${TF_VERSION} installed"

    check_command "kubectl" "brew install kubectl" || exit 1
    print_status "kubectl installed"

    check_command "helm" "brew install helm" || exit 1
    print_status "helm installed"

    check_command "jq" "brew install jq" || exit 1
    print_status "jq installed"
}

check_aws_prerequisites() {
    check_command "aws" "brew install awscli" || exit 1

    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_status "AWS CLI configured (Account: ${AWS_ACCOUNT_ID})"
}

check_azure_prerequisites() {
    check_command "az" "brew install azure-cli" || exit 1

    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi

    AZURE_SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_status "Azure CLI configured (Subscription: ${AZURE_SUBSCRIPTION_NAME})"

    # Check kubelogin for AKS
    if ! command -v kubelogin &> /dev/null; then
        print_warning "kubelogin is not installed. Install with: brew install Azure/kubelogin/kubelogin"
    fi
}

check_gcp_prerequisites() {
    check_command "gcloud" "brew install google-cloud-sdk" || exit 1

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "Not logged in to GCP. Run 'gcloud auth login' first."
        exit 1
    fi

    GCP_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$GCP_PROJECT" ]]; then
        print_error "No GCP project configured. Run 'gcloud config set project <PROJECT_ID>' first."
        exit 1
    fi
    print_status "GCP CLI configured (Project: ${GCP_PROJECT})"

    # Check gke-gcloud-auth-plugin
    if ! gcloud components list 2>/dev/null | grep -q "gke-gcloud-auth-plugin.*Installed"; then
        print_warning "gke-gcloud-auth-plugin may not be installed. Install with: gcloud components install gke-gcloud-auth-plugin"
    fi
}

# =============================================================================
# Terraform Functions
# =============================================================================
terraform_init() {
    local tf_dir="$1"
    print_info "Initializing Terraform in ${tf_dir}..."
    terraform -chdir="$tf_dir" init -upgrade
}

terraform_plan() {
    local tf_dir="$1"
    print_info "Planning Terraform deployment..."
    terraform -chdir="$tf_dir" plan -out=tfplan
}

terraform_apply() {
    local tf_dir="$1"
    print_info "Applying Terraform deployment..."
    terraform -chdir="$tf_dir" apply tfplan
}

terraform_destroy() {
    local tf_dir="$1"
    print_info "Destroying Terraform resources..."
    terraform -chdir="$tf_dir" destroy -auto-approve
}

terraform_output() {
    local tf_dir="$1"
    local output_name="$2"
    terraform -chdir="$tf_dir" output -raw "$output_name" 2>/dev/null
}

# =============================================================================
# Kubernetes Functions
# =============================================================================
wait_for_pods() {
    local namespace="$1"
    local label="${2:-}"
    local timeout="${3:-300}"

    print_info "Waiting for pods in ${namespace} to be ready..."

    local selector=""
    if [[ -n "$label" ]]; then
        selector="-l $label"
    fi

    kubectl wait --for=condition=ready pod \
        -n "$namespace" $selector \
        --timeout="${timeout}s" 2>/dev/null || {
        print_warning "Some pods may not be ready yet"
        return 1
    }
    print_status "Pods in ${namespace} are ready"
}

delete_namespace_resources() {
    local namespace="$1"

    print_info "Cleaning up resources in ${namespace}..."

    # Delete common blocking resources
    kubectl delete externalsecrets --all -n "$namespace" 2>/dev/null || true
    kubectl delete pvc --all -n "$namespace" 2>/dev/null || true
    kubectl delete svc --field-selector spec.type=LoadBalancer -n "$namespace" 2>/dev/null || true
}

cleanup_kyverno() {
    print_info "Removing Kyverno webhooks and policies..."
    kubectl delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration kyverno-resource-mutating-webhook-cfg 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg 2>/dev/null || true
    kubectl delete clusterpolicy --all 2>/dev/null || true
    kubectl delete policyexception --all -A 2>/dev/null || true
}

cleanup_tetragon() {
    print_info "Removing Tetragon policies..."
    kubectl delete tracingpolicies --all 2>/dev/null || true
}

# =============================================================================
# Confirmation Functions
# =============================================================================
confirm_action() {
    local message="$1"
    local confirm_word="${2:-yes}"

    echo -e "${YELLOW}${message}${NC}"
    read -p "Type '${confirm_word}' to confirm: " response

    if [[ "$response" != "$confirm_word" ]]; then
        print_info "Action cancelled"
        return 1
    fi
    return 0
}

# =============================================================================
# Path Functions
# =============================================================================
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

get_project_root() {
    local script_dir
    script_dir="$(get_script_dir)"
    echo "$(dirname "$script_dir")"
}