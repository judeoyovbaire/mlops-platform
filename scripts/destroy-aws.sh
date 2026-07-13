#!/bin/bash
set -euo pipefail

# MLOps Platform - AWS Infrastructure Destroy Script
# Handles cleanup of resources that can cause terraform destroy issues:
# Kyverno webhooks, Karpenter nodes/instance profiles, CloudWatch log groups

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/common/common.sh"

TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/aws/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_AWS_REGION="eu-west-1"

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

    # 4. Delete KServe InferenceServices outright (finalizers first). Only
    # patching finalizers is not enough: a CI deploy dispatched after this
    # phase recreated the InferenceService, its controller was uninstalled
    # mid-destroy, and the orphaned finalizer wedged the mlops namespace
    # for the whole terraform run (July teardown). Deleting now, while the
    # controller still exists, lets finalizer processing complete cleanly -
    # and the runbook requires CI dispatches to be halted before starting.
    print_info "Removing KServe InferenceServices..."
    for ns in $(kubectl get inferenceservices -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
        for isvc in $(kubectl get inferenceservices -n "$ns" --no-headers 2>/dev/null | awk '{print $1}'); do
            kubectl patch inferenceservice "$isvc" -n "$ns" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
            kubectl delete inferenceservice "$isvc" -n "$ns" --wait=false --ignore-not-found 2>/dev/null || true
        done
    done

    # 5. Clean up Karpenter resources (prevents orphaned nodes)
    print_info "Removing Karpenter resources..."
    kubectl delete nodeclaims --all --ignore-not-found 2>/dev/null || true
    kubectl delete nodepools --all --ignore-not-found 2>/dev/null || true
    kubectl delete ec2nodeclasses --all --ignore-not-found 2>/dev/null || true

    # 6. Delete other webhook configurations that might block
    print_info "Removing other webhooks that might block deletion..."
    kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=tetragon --ignore-not-found 2>/dev/null || true

    # Give resources time to clean up
    print_info "Waiting for resources to terminate..."
    sleep 10

    print_status "Kubernetes cleanup complete"
}

# Purge AWS Backup recovery points - vault deletion fails while any exist
# (July teardown: terraform destroy errored with InvalidRequestException
# "Backup vault cannot be deleted because it contains recovery points").
purge_backup_recovery_points() {
    echo ""
    echo -e "${CYAN}Phase 1.5: Backup Recovery Point Purge${NC}"
    echo "========================================"

    VAULTS=$(aws backup list-backup-vaults --region "${AWS_REGION}" \
        --query "BackupVaultList[?contains(BackupVaultName, '${CLUSTER_NAME}')].BackupVaultName" \
        --output text 2>/dev/null)

    for vault in $VAULTS; do
        [[ -z "$vault" || "$vault" == "None" ]] && continue
        print_info "Purging recovery points in vault: $vault"
        for rp in $(aws backup list-recovery-points-by-backup-vault \
            --backup-vault-name "$vault" --region "${AWS_REGION}" \
            --query 'RecoveryPoints[].RecoveryPointArn' --output text 2>/dev/null); do
            [[ -z "$rp" || "$rp" == "None" ]] && continue
            aws backup delete-recovery-point --backup-vault-name "$vault" \
                --recovery-point-arn "$rp" --region "${AWS_REGION}" 2>/dev/null || true
        done
        # Deletion is async - give the vault a moment to empty
        for _ in $(seq 1 12); do
            REMAINING=$(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault" --region "${AWS_REGION}" \
                --query 'length(RecoveryPoints)' --output text 2>/dev/null || echo 0)
            [[ "$REMAINING" == "0" ]] && break
            sleep 5
        done
        print_status "  Vault $vault emptied"
    done

    [[ -z "$VAULTS" ]] && print_info "No backup vaults found"
    print_status "Backup recovery point purge complete"
}

# Unwedge namespaces stuck Terminating on orphaned finalizers before a
# terraform retry - by then controllers are gone and nothing else will.
clear_stuck_namespaces() {
    kubectl cluster-info &>/dev/null || return 0

    STUCK=$(kubectl get namespaces --no-headers 2>/dev/null | awk '$2=="Terminating"{print $1}')
    for ns in $STUCK; do
        print_info "Namespace $ns stuck Terminating - clearing resource finalizers"
        for isvc in $(kubectl get inferenceservices -n "$ns" --no-headers 2>/dev/null | awk '{print $1}'); do
            kubectl patch inferenceservice "$isvc" -n "$ns" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
        done
    done
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

    # 2. Delete CloudWatch log groups (prevents "already exists" on
    # reinstall). vpc-flow-logs is included explicitly: in-flight flow-log
    # delivery re-creates its group AFTER terraform deletes it - the July 13
    # rebuild collided on exactly that orphan.
    print_info "Cleaning up CloudWatch log groups..."
    for lg in "/aws/eks/${CLUSTER_NAME}/cluster" "/aws/vpc-flow-logs/${CLUSTER_NAME}"; do
        if aws logs delete-log-group \
            --log-group-name "$lg" \
            --region "${AWS_REGION}" 2>/dev/null; then
            print_status "  Deleted: $lg"
        else
            print_info "  Already gone: $lg"
        fi
    done

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

    # 5. Delete orphaned EBS volumes from PVCs (the CSI driver's volumes
    # survive cluster deletion when the cluster goes before the PVCs -
    # July left three eventbus volumes billing quietly)
    print_info "Checking for orphaned EBS volumes..."
    VOLUMES=$(aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
                  "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" \
        --query 'Volumes[*].VolumeId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    VOLUMES="$VOLUMES $(aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
                  "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_NAME}" \
        --query 'Volumes[*].VolumeId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)"

    for vol in $(echo "$VOLUMES" | tr ' ' '\n' | sort -u); do
        if [[ -n "$vol" && "$vol" != "None" ]]; then
            print_info "  Deleting volume: $vol"
            aws ec2 delete-volume --volume-id "$vol" \
                --region "${AWS_REGION}" 2>/dev/null || true
        fi
    done

    # 6. Force-delete cluster secrets still in their recovery window.
    # recovery_window_in_days=0 in dev Terraform handles the common case;
    # this sweeps stragglers (e.g. stacks created before that change).
    print_info "Checking for soft-deleted Secrets Manager entries..."
    SECRETS=$(aws secretsmanager list-secrets \
        --include-planned-deletion \
        --region "${AWS_REGION}" \
        --query "SecretList[?starts_with(Name, '${CLUSTER_NAME}/')].Name" \
        --output text 2>/dev/null)

    for secret in $SECRETS; do
        if [[ -n "$secret" && "$secret" != "None" ]]; then
            print_info "  Force-deleting secret: $secret"
            aws secretsmanager delete-secret --secret-id "$secret" \
                --force-delete-without-recovery \
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

    # Check log groups (both prefixes - flow-log delivery re-creates its
    # group after terraform destroy)
    REMAINING_LGS=""
    for lg_prefix in "/aws/eks/${CLUSTER_NAME}" "/aws/vpc-flow-logs/${CLUSTER_NAME}"; do
        FOUND=$(aws logs describe-log-groups \
            --log-group-name-prefix "$lg_prefix" \
            --region "${AWS_REGION}" \
            --query 'logGroups[0].logGroupName' \
            --output text 2>/dev/null)
        [[ -n "$FOUND" && "$FOUND" != "None" ]] && REMAINING_LGS="$REMAINING_LGS $FOUND"
    done
    if [[ -n "$REMAINING_LGS" ]]; then
        print_warning "CloudWatch log groups still exist:$REMAINING_LGS"
        issues=$((issues + 1))
    else
        print_status "CloudWatch log groups deleted"
    fi

    # Check for cluster S3 buckets (force_destroy should have emptied them)
    REMAINING_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, '${CLUSTER_NAME}-')].Name" \
        --output text 2>/dev/null)
    if [[ -n "$REMAINING_BUCKETS" && "$REMAINING_BUCKETS" != "None" ]]; then
        print_warning "Remaining S3 buckets: $REMAINING_BUCKETS"
        issues=$((issues + 1))
    else
        print_status "No cluster S3 buckets remain"
    fi

    # Check for backup vaults with recovery points
    REMAINING_VAULTS=$(aws backup list-backup-vaults --region "${AWS_REGION}" \
        --query "BackupVaultList[?contains(BackupVaultName, '${CLUSTER_NAME}')].BackupVaultName" \
        --output text 2>/dev/null)
    if [[ -n "$REMAINING_VAULTS" && "$REMAINING_VAULTS" != "None" ]]; then
        print_warning "Remaining backup vaults: $REMAINING_VAULTS"
        issues=$((issues + 1))
    else
        print_status "No backup vaults remain"
    fi

    # Check for orphaned EBS volumes
    REMAINING_VOLUMES=$(aws ec2 describe-volumes \
        --filters "Name=status,Values=available" \
                  "Name=tag:KubernetesCluster,Values=${CLUSTER_NAME}" \
        --query 'Volumes[*].VolumeId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null)
    if [[ -n "$REMAINING_VOLUMES" && "$REMAINING_VOLUMES" != "None" ]]; then
        print_warning "Remaining EBS volumes: $REMAINING_VOLUMES"
        issues=$((issues + 1))
    else
        print_status "No orphaned EBS volumes"
    fi

    # Check for cluster secrets (including soft-deleted)
    REMAINING_SECRETS=$(aws secretsmanager list-secrets \
        --include-planned-deletion \
        --region "${AWS_REGION}" \
        --query "SecretList[?starts_with(Name, '${CLUSTER_NAME}/')].Name" \
        --output text 2>/dev/null)
    if [[ -n "$REMAINING_SECRETS" && "$REMAINING_SECRETS" != "None" ]]; then
        print_warning "Remaining secrets: $REMAINING_SECRETS"
        issues=$((issues + 1))
    else
        print_status "No cluster secrets remain"
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
    print_warning "BEFORE destroying: cancel in-flight CI dispatches (deploy-infra /"
    print_warning "deploy-model). A deploy racing the teardown recreates resources"
    print_warning "mid-destroy - a July run recreated an InferenceService whose"
    print_warning "orphaned finalizer wedged its namespace for the whole destroy."
    echo ""

    # Best-effort check for racing CI runs (needs gh CLI + repo auth)
    if command -v gh &>/dev/null; then
        ACTIVE_RUNS=$(gh run list --workflow=ci-cd.yaml \
            --status in_progress --json databaseId --jq 'length' 2>/dev/null || echo 0)
        if [[ "${ACTIVE_RUNS:-0}" != "0" ]]; then
            print_warning "${ACTIVE_RUNS} ci-cd run(s) currently in progress!"
            print_warning "Cancel them first: gh run list --workflow=ci-cd.yaml --status in_progress"
            if [[ "$FORCE" != true ]]; then
                read -p "Continue anyway? (yes/no): " -r
                echo
                [[ $REPLY == "yes" ]] || { print_info "Destroy cancelled"; exit 0; }
            fi
        fi
    fi

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
    purge_backup_recovery_points

    # Run terraform destroy (retry once if it fails)
    if ! terraform_destroy; then
        print_warning "First terraform destroy failed, running additional cleanup..."
        clear_stuck_namespaces
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
    echo "  - Orphaned EC2 instances, ENIs, and PVC-created EBS volumes"
    echo "  - Backup vault recovery points (block vault deletion)"
    echo "  - KServe finalizers wedging namespace deletion"
    echo "  - Soft-deleted Secrets Manager entries"
    echo ""
    echo "See docs/runbooks/teardown.md for the full procedure."
    exit 0
fi

main "$@"