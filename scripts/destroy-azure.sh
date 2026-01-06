#!/bin/bash
set -euo pipefail

# MLOps Platform - Azure Infrastructure Destroy Script
# Handles cleanup of resources that can cause terraform destroy issues:
# Kyverno webhooks, KEDA ScaledObjects, Managed Identities, resource locks

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
DEFAULT_AZURE_LOCATION="northeurope"
DEFAULT_RESOURCE_GROUP="mlops-platform-dev-rg"

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

# Get cluster configuration
get_cluster_config() {
    cd "${TF_DIR}"

    # Try to get from terraform output first
    if terraform output cluster_name &>/dev/null; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null)
        RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)
        AZURE_LOCATION=$(terraform output -raw location 2>/dev/null || echo "$DEFAULT_AZURE_LOCATION")
    fi

    # Fallback to defaults
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
    AZURE_LOCATION=${AZURE_LOCATION:-$DEFAULT_AZURE_LOCATION}

    export CLUSTER_NAME RESOURCE_GROUP AZURE_LOCATION
}

# Pre-destroy cleanup to handle stuck Kubernetes resources
pre_destroy_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 1: Kubernetes Resource Cleanup${NC}"
    echo "========================================"

    # Check if cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        print_warning "Cluster not accessible, skipping Kubernetes cleanup"
        return 0
    fi

    # 1. Delete Kyverno webhooks first (they can block their own deletion)
    print_info "Removing Kyverno webhooks..."
    kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/instance=kyverno --ignore-not-found 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/instance=kyverno --ignore-not-found 2>/dev/null || true
    # Also try by name pattern
    kubectl delete validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg kyverno-resource-validating-webhook-cfg --ignore-not-found 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration kyverno-policy-mutating-webhook-cfg kyverno-resource-mutating-webhook-cfg --ignore-not-found 2>/dev/null || true

    # 2. Delete Kyverno ClusterPolicies (they create generated resources)
    print_info "Removing Kyverno policies..."
    kubectl delete clusterpolicies --all --ignore-not-found 2>/dev/null || true
    kubectl delete policyexceptions --all -A --ignore-not-found 2>/dev/null || true

    # 3. Force delete Kyverno namespace if stuck
    if kubectl get namespace kyverno &>/dev/null; then
        print_info "Removing Kyverno namespace..."
        kubectl delete namespace kyverno --wait=false --ignore-not-found 2>/dev/null || true
        sleep 2
        # Remove finalizers if stuck
        kubectl patch namespace kyverno -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    fi

    # 4. Clean up KEDA resources (prevents orphaned Azure resources)
    print_info "Removing KEDA resources..."
    kubectl delete scaledobjects --all -A --ignore-not-found 2>/dev/null || true
    kubectl delete scaledjobs --all -A --ignore-not-found 2>/dev/null || true
    kubectl delete triggerauthentications --all -A --ignore-not-found 2>/dev/null || true
    kubectl delete clustertriggerauthentications --all --ignore-not-found 2>/dev/null || true

    # 5. Delete other webhook configurations that might block
    print_info "Removing other webhooks that might block deletion..."
    kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=tetragon --ignore-not-found 2>/dev/null || true

    # 6. Delete External Secrets resources
    print_info "Removing External Secrets resources..."
    kubectl delete externalsecrets --all -A --ignore-not-found 2>/dev/null || true
    kubectl delete clustersecretstores --all --ignore-not-found 2>/dev/null || true

    # 7. Delete LoadBalancer services to release Azure LB resources
    print_info "Removing LoadBalancer services..."
    kubectl delete svc -A -l app.kubernetes.io/name=ingress-nginx --ignore-not-found 2>/dev/null || true

    # Give resources time to clean up
    print_info "Waiting for resources to terminate..."
    sleep 10

    print_status "Kubernetes cleanup complete"
}

# Run terraform destroy
terraform_destroy() {
    echo ""
    echo -e "${CYAN}Phase 2: Terraform Destroy${NC}"
    echo "========================================"

    cd "${TF_DIR}"

    print_info "Running terraform destroy..."

    # Run terraform destroy with auto-approve
    if terraform destroy -auto-approve; then
        print_status "Terraform destroy completed successfully"
        return 0
    else
        print_warning "Terraform destroy encountered errors"
        return 1
    fi
}

# Post-destroy cleanup for orphaned Azure resources
post_destroy_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 3: Azure Orphaned Resource Cleanup${NC}"
    echo "========================================"

    # 1. Delete resource group if it still exists (this cleans up everything)
    print_info "Checking for orphaned resource group..."
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        print_info "  Resource group still exists, attempting deletion..."

        # Remove any resource locks first
        LOCKS=$(az lock list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null)
        for lock in $LOCKS; do
            if [[ -n "$lock" ]]; then
                print_info "  Removing lock: $lock"
                az lock delete --name "$lock" --resource-group "${RESOURCE_GROUP}" 2>/dev/null || true
            fi
        done

        # Try to delete the resource group
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    else
        print_info "  Resource group already deleted"
    fi

    # 2. Clean up orphaned managed identities in other resource groups
    print_info "Checking for orphaned managed identities..."
    MC_RESOURCE_GROUP="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${AZURE_LOCATION}"
    if az group show --name "${MC_RESOURCE_GROUP}" &>/dev/null; then
        print_info "  Found AKS-managed resource group: ${MC_RESOURCE_GROUP}"
        print_info "  This will be deleted when the AKS cluster is fully removed"
    fi

    # 3. Clean up any orphaned public IPs
    print_info "Checking for orphaned public IPs..."
    ORPHANED_IPS=$(az network public-ip list \
        --query "[?contains(name, '${CLUSTER_NAME}')].{name:name, resourceGroup:resourceGroup}" \
        -o tsv 2>/dev/null)

    while IFS=$'\t' read -r name rg; do
        if [[ -n "$name" && -n "$rg" ]]; then
            print_info "  Deleting public IP: $name in $rg"
            az network public-ip delete --name "$name" --resource-group "$rg" 2>/dev/null || true
        fi
    done <<< "$ORPHANED_IPS"

    # 4. Clean up orphaned disks
    print_info "Checking for orphaned disks..."
    ORPHANED_DISKS=$(az disk list \
        --query "[?contains(name, '${CLUSTER_NAME}') && managedBy==null].{name:name, resourceGroup:resourceGroup}" \
        -o tsv 2>/dev/null)

    while IFS=$'\t' read -r name rg; do
        if [[ -n "$name" && -n "$rg" ]]; then
            print_info "  Deleting orphaned disk: $name in $rg"
            az disk delete --name "$name" --resource-group "$rg" --yes 2>/dev/null || true
        fi
    done <<< "$ORPHANED_DISKS"

    print_status "Azure cleanup complete"
}

# Verify cleanup
verify_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 4: Verification${NC}"
    echo "========================================"

    print_info "Verifying cleanup..."

    # Check for remaining resources
    local issues=0

    # Check AKS cluster
    if az aks show --name "${CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        print_error "AKS cluster still exists: ${CLUSTER_NAME}"
        issues=$((issues + 1))
    else
        print_status "AKS cluster deleted"
    fi

    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        # Check if it's being deleted
        STATE=$(az group show --name "${RESOURCE_GROUP}" --query 'properties.provisioningState' -o tsv 2>/dev/null)
        if [[ "$STATE" == "Deleting" ]]; then
            print_warning "Resource group is being deleted (this may take a few minutes)"
        else
            print_error "Resource group still exists: ${RESOURCE_GROUP}"
            issues=$((issues + 1))
        fi
    else
        print_status "Resource group deleted"
    fi

    # Check for MC_ resource group (AKS-managed)
    MC_RESOURCE_GROUP="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${AZURE_LOCATION}"
    if az group show --name "${MC_RESOURCE_GROUP}" &>/dev/null; then
        STATE=$(az group show --name "${MC_RESOURCE_GROUP}" --query 'properties.provisioningState' -o tsv 2>/dev/null)
        if [[ "$STATE" == "Deleting" ]]; then
            print_warning "AKS-managed resource group is being deleted"
        else
            print_warning "AKS-managed resource group still exists: ${MC_RESOURCE_GROUP}"
            issues=$((issues + 1))
        fi
    else
        print_status "AKS-managed resource group deleted"
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        print_status "All resources cleaned up successfully!"
    else
        print_warning "$issues issue(s) found - resources may still be deleting or require manual cleanup"
        print_info "Run 'az group list --query \"[?contains(name, '${CLUSTER_NAME}')]\"' to check status"
    fi

    return $issues
}

# Main destroy function
main() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  MLOps Platform - Azure Destroy       ${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""

    # Check for --force flag
    FORCE=false
    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        FORCE=true
    fi

    print_warning "This will delete ALL resources including:"
    echo "  - AKS cluster and all workloads"
    echo "  - PostgreSQL database (data will be lost)"
    echo "  - Storage account and artifacts"
    echo "  - Key Vault and secrets"
    echo "  - Virtual network and subnets"
    echo "  - Container registry"
    echo ""

    if [[ "$FORCE" != true ]]; then
        read -p "Are you sure you want to destroy? (yes/no): " -r
        echo
        if [[ ! $REPLY == "yes" ]]; then
            print_info "Destroy cancelled"
            exit 0
        fi
    fi

    # Get cluster configuration
    get_cluster_config
    print_info "Cluster: ${CLUSTER_NAME}"
    print_info "Resource Group: ${RESOURCE_GROUP}"
    print_info "Location: ${AZURE_LOCATION}"
    echo ""

    # Update kubeconfig for cleanup
    print_info "Updating kubeconfig for cleanup..."
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CLUSTER_NAME}" \
        --overwrite-existing 2>/dev/null || true

    if command -v kubelogin &>/dev/null; then
        kubelogin convert-kubeconfig -l azurecli 2>/dev/null || true
    fi

    # Run all cleanup phases
    pre_destroy_cleanup

    # Run terraform destroy (retry once if it fails)
    if ! terraform_destroy; then
        print_warning "First terraform destroy failed, running additional cleanup..."
        post_destroy_cleanup
        print_info "Retrying terraform destroy..."
        terraform_destroy || true
    fi

    post_destroy_cleanup
    verify_cleanup

    echo ""
    print_status "Destroy process complete!"
    print_info "Run 'kubectl config delete-context ${CLUSTER_NAME}' to clean up local kubeconfig"
}

# Handle help
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--force]"
    echo ""
    echo "Destroys all MLOps platform Azure infrastructure with proper cleanup."
    echo ""
    echo "Options:"
    echo "  --force, -f   Skip confirmation prompt"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "This script handles common destroy issues:"
    echo "  - Kyverno webhooks blocking deletion"
    echo "  - KEDA ScaledObjects and triggers"
    echo "  - LoadBalancer services blocking Azure LB deletion"
    echo "  - Resource locks preventing deletion"
    echo "  - Orphaned disks and public IPs"
    exit 0
fi

main "$@"
