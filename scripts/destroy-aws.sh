#!/bin/bash
set -euo pipefail

# MLOps Platform - AWS Infrastructure Destroy Script
# Handles cleanup of resources that can cause terraform destroy issues:
# Kyverno webhooks, Karpenter nodes/instance profiles, CloudWatch log groups

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
TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/aws/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_AWS_REGION="eu-west-1"

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
        AWS_REGION=$(terraform output -raw configure_kubectl 2>/dev/null | grep -oE '\-\-region [a-z0-9-]+' | awk '{print $2}')
    fi

    # Fallback to defaults
    CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
    AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}

    export CLUSTER_NAME AWS_REGION
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

    # 4. Clean up Karpenter resources (prevents orphaned nodes)
    print_info "Removing Karpenter resources..."
    kubectl delete nodeclaims --all --ignore-not-found 2>/dev/null || true
    kubectl delete nodepools --all --ignore-not-found 2>/dev/null || true
    kubectl delete ec2nodeclasses --all --ignore-not-found 2>/dev/null || true

    # 5. Delete other webhook configurations that might block
    print_info "Removing other webhooks that might block deletion..."
    kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=tetragon --ignore-not-found 2>/dev/null || true

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

# Post-destroy cleanup for orphaned AWS resources
post_destroy_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 3: AWS Orphaned Resource Cleanup${NC}"
    echo "========================================"

    # 1. Delete orphaned Karpenter instance profiles
    print_info "Cleaning up Karpenter instance profiles..."
    PROFILES=$(aws iam list-instance-profiles \
        --query "InstanceProfiles[?contains(InstanceProfileName, '${CLUSTER_NAME}')].InstanceProfileName" \
        --output text 2>/dev/null)

    for profile in $PROFILES; do
        if [[ -n "$profile" && "$profile" != "None" ]]; then
            print_info "  Deleting: $profile"
            # Remove role from instance profile first
            ROLES=$(aws iam get-instance-profile --instance-profile-name "$profile" \
                --query 'InstanceProfile.Roles[*].RoleName' --output text 2>/dev/null)
            for role in $ROLES; do
                if [[ -n "$role" && "$role" != "None" ]]; then
                    aws iam remove-role-from-instance-profile \
                        --instance-profile-name "$profile" \
                        --role-name "$role" 2>/dev/null || true
                fi
            done
            aws iam delete-instance-profile --instance-profile-name "$profile" 2>/dev/null || true
        fi
    done

    # 2. Delete CloudWatch log group (prevents "already exists" on reinstall)
    print_info "Cleaning up CloudWatch log groups..."
    if aws logs delete-log-group \
        --log-group-name "/aws/eks/${CLUSTER_NAME}/cluster" \
        --region "${AWS_REGION}" 2>/dev/null; then
        print_status "  Deleted: /aws/eks/${CLUSTER_NAME}/cluster"
    else
        print_info "  Log group already deleted or doesn't exist"
    fi

    # 3. Terminate any orphaned EC2 instances from Karpenter
    print_info "Checking for orphaned EC2 instances..."
    ORPHANED_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
                  "Name=instance-state-name,Values=running,pending,stopping" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)

    if [[ -n "$ORPHANED_INSTANCES" && "$ORPHANED_INSTANCES" != "None" ]]; then
        print_info "  Terminating: $ORPHANED_INSTANCES"
        aws ec2 terminate-instances \
            --instance-ids $ORPHANED_INSTANCES \
            --region "${AWS_REGION}" 2>/dev/null || true

        # Wait for instances to terminate
        print_info "  Waiting for instances to terminate..."
        aws ec2 wait instance-terminated \
            --instance-ids $ORPHANED_INSTANCES \
            --region "${AWS_REGION}" 2>/dev/null || true
    else
        print_info "  No orphaned instances found"
    fi

    # 4. Clean up any dangling ENIs (can block VPC/subnet deletion)
    print_info "Checking for dangling network interfaces..."
    ENIS=$(aws ec2 describe-network-interfaces \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
                  "Name=status,Values=available" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)

    for eni in $ENIS; do
        if [[ -n "$eni" && "$eni" != "None" ]]; then
            print_info "  Deleting ENI: $eni"
            aws ec2 delete-network-interface \
                --network-interface-id "$eni" \
                --region "${AWS_REGION}" 2>/dev/null || true
        fi
    done

    print_status "AWS cleanup complete"
}

# Verify cleanup
verify_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 4: Verification${NC}"
    echo "========================================"

    print_info "Verifying cleanup..."

    # Check for remaining resources
    local issues=0

    # Check EKS cluster
    if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        print_error "EKS cluster still exists: ${CLUSTER_NAME}"
        issues=$((issues + 1))
    else
        print_status "EKS cluster deleted"
    fi

    # Check for instance profiles
    REMAINING_PROFILES=$(aws iam list-instance-profiles \
        --query "InstanceProfiles[?contains(InstanceProfileName, '${CLUSTER_NAME}')].InstanceProfileName" \
        --output text 2>/dev/null)
    if [[ -n "$REMAINING_PROFILES" && "$REMAINING_PROFILES" != "None" ]]; then
        print_warning "Remaining instance profiles: $REMAINING_PROFILES"
        issues=$((issues + 1))
    else
        print_status "No orphaned instance profiles"
    fi

    # Check for running instances
    REMAINING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
                  "Name=instance-state-name,Values=running,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    if [[ -n "$REMAINING_INSTANCES" && "$REMAINING_INSTANCES" != "None" ]]; then
        print_warning "Remaining instances: $REMAINING_INSTANCES"
        issues=$((issues + 1))
    else
        print_status "No orphaned EC2 instances"
    fi

    # Check log group
    if aws logs describe-log-groups \
        --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}/cluster" \
        --region "${AWS_REGION}" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
        print_warning "CloudWatch log group still exists"
        issues=$((issues + 1))
    else
        print_status "CloudWatch log group deleted"
    fi

    echo ""
    if [[ $issues -eq 0 ]]; then
        print_status "All resources cleaned up successfully!"
    else
        print_warning "$issues issue(s) found - manual cleanup may be required"
    fi

    return $issues
}

# Main destroy function
main() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  MLOps Platform - Infrastructure Destroy${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""

    # Check for --force flag
    FORCE=false
    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        FORCE=true
    fi

    print_warning "This will delete ALL resources including:"
    echo "  - EKS cluster and all workloads"
    echo "  - RDS database (data will be lost)"
    echo "  - S3 bucket and artifacts"
    echo "  - VPC and networking"
    echo "  - CloudWatch log groups"
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
    print_info "Region: ${AWS_REGION}"
    echo ""

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
    echo "Destroys all MLOps platform AWS infrastructure with proper cleanup."
    echo ""
    echo "Options:"
    echo "  --force, -f   Skip confirmation prompt"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "This script handles common destroy issues:"
    echo "  - Kyverno webhooks blocking deletion"
    echo "  - Karpenter orphaned instance profiles"
    echo "  - CloudWatch log groups (cause reinstall errors)"
    echo "  - Orphaned EC2 instances and ENIs"
    exit 0
fi

main "$@"