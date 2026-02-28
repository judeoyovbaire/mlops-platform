#!/bin/bash
set -euo pipefail

# MLOps Platform - GCP GKE Destruction
# Safely destroys all GCP resources with proper cleanup order

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/common/common.sh"

TF_DIR="${PROJECT_ROOT}/infrastructure/terraform/environments/gcp/dev"

# Default configuration
DEFAULT_CLUSTER_NAME="mlops-platform-dev"
DEFAULT_GCP_REGION="europe-west4"
DEFAULT_GCP_ZONE="europe-west4-a"

# Get configuration
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
GCP_REGION=${GCP_REGION:-$DEFAULT_GCP_REGION}
GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

# Phase 1: Kubernetes cleanup
phase1_kubernetes_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 1: Kubernetes Resource Cleanup${NC}"
    echo "========================================"

    # Try to connect to cluster
    gcloud container clusters get-credentials "$CLUSTER_NAME" \
        --zone "$GCP_ZONE" \
        --project "$GCP_PROJECT" 2>/dev/null || {
        print_warning "Cannot connect to cluster - may already be deleted"
        return 0
    }

    # Delete Kyverno webhooks (can block namespace deletion)
    print_info "Removing Kyverno webhooks..."
    kubectl delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration kyverno-resource-mutating-webhook-cfg 2>/dev/null || true
    kubectl delete validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg 2>/dev/null || true

    # Delete Kyverno policies
    print_info "Removing Kyverno policies..."
    kubectl delete clusterpolicy --all 2>/dev/null || true
    kubectl delete policyexception --all -A 2>/dev/null || true

    # Force delete Kyverno namespace if stuck
    kubectl delete namespace kyverno --grace-period=0 --force 2>/dev/null || true

    # Remove KServe InferenceService finalizers (controller is destroyed before namespace)
    print_info "Removing KServe InferenceService finalizers..."
    for ns in $(kubectl get inferenceservices -A --no-headers 2>/dev/null | awk '{print $1}'); do
        for isvc in $(kubectl get inferenceservices -n "$ns" --no-headers 2>/dev/null | awk '{print $1}'); do
            kubectl patch inferenceservice "$isvc" -n "$ns" --type=json \
                -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
        done
    done

    # Delete External Secrets resources
    print_info "Removing External Secrets resources..."
    kubectl delete externalsecrets --all -A 2>/dev/null || true
    kubectl delete clustersecretstore --all 2>/dev/null || true

    # Delete Tetragon policies
    print_info "Removing Tetragon policies..."
    kubectl delete tracingpolicies --all 2>/dev/null || true

    # Delete LoadBalancer services (release external IPs)
    print_info "Removing LoadBalancer services..."
    kubectl delete svc -A --field-selector spec.type=LoadBalancer 2>/dev/null || true

    # Wait for services to be deleted
    sleep 10

    print_status "Kubernetes cleanup complete"
}

# Phase 2: Terraform destroy
phase2_terraform_destroy() {
    echo ""
    echo -e "${CYAN}Phase 2: Terraform Destroy${NC}"
    echo "========================================"

    cd "${TF_DIR}"

    if [[ ! -f "terraform.tfstate" ]] && [[ ! -d ".terraform" ]]; then
        print_warning "No Terraform state found - may already be destroyed"
        return 0
    fi

    # Initialize if needed
    print_info "Initializing Terraform..."
    terraform init -upgrade 2>/dev/null || true

    # Destroy
    print_info "Running terraform destroy..."
    if terraform destroy -auto-approve; then
        print_status "Terraform destroy completed successfully"
        return 0
    else
        print_warning "Terraform destroy encountered errors"
        return 1
    fi
}

# Phase 3: GCP orphaned resources cleanup
phase3_gcp_cleanup() {
    echo ""
    echo -e "${CYAN}Phase 3: GCP Orphaned Resources Cleanup${NC}"
    echo "========================================"

    # Delete orphaned persistent disks
    print_info "Checking for orphaned disks..."
    DISKS=$(gcloud compute disks list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name,zone)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$DISKS" ]]; then
        echo "$DISKS" | while read -r disk zone; do
            if [[ -n "$disk" ]] && [[ -n "$zone" ]]; then
                print_info "Deleting disk: $disk"
                gcloud compute disks delete "$disk" \
                    --zone="$zone" \
                    --project="$GCP_PROJECT" \
                    --quiet 2>/dev/null || true
            fi
        done
    fi

    # Delete orphaned forwarding rules
    print_info "Checking for orphaned forwarding rules..."
    FWD_RULES=$(gcloud compute forwarding-rules list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name,region)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$FWD_RULES" ]]; then
        echo "$FWD_RULES" | while read -r rule region; do
            if [[ -n "$rule" ]]; then
                print_info "Deleting forwarding rule: $rule"
                if [[ -n "$region" ]]; then
                    gcloud compute forwarding-rules delete "$rule" \
                        --region="$region" \
                        --project="$GCP_PROJECT" \
                        --quiet 2>/dev/null || true
                else
                    gcloud compute forwarding-rules delete "$rule" \
                        --global \
                        --project="$GCP_PROJECT" \
                        --quiet 2>/dev/null || true
                fi
            fi
        done
    fi

    # Delete orphaned backend services
    print_info "Checking for orphaned backend services..."
    BACKENDS=$(gcloud compute backend-services list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$BACKENDS" ]]; then
        for backend in $BACKENDS; do
            print_info "Deleting backend service: $backend"
            gcloud compute backend-services delete "$backend" \
                --global \
                --project="$GCP_PROJECT" \
                --quiet 2>/dev/null || true
        done
    fi

    # Delete orphaned health checks
    print_info "Checking for orphaned health checks..."
    HEALTH_CHECKS=$(gcloud compute health-checks list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$HEALTH_CHECKS" ]]; then
        for hc in $HEALTH_CHECKS; do
            print_info "Deleting health check: $hc"
            gcloud compute health-checks delete "$hc" \
                --project="$GCP_PROJECT" \
                --quiet 2>/dev/null || true
        done
    fi

    print_status "GCP cleanup complete"
}

# Phase 4: Verification
phase4_verification() {
    echo ""
    echo -e "${CYAN}Phase 4: Verification${NC}"
    echo "========================================"

    # Check GKE cluster
    print_info "Verifying GKE cluster deletion..."
    if gcloud container clusters describe "$CLUSTER_NAME" \
        --zone "$GCP_ZONE" \
        --project "$GCP_PROJECT" &>/dev/null; then
        print_warning "GKE cluster still exists (may be deleting)"
    else
        print_status "GKE cluster deleted"
    fi

    # Check Cloud SQL
    print_info "Verifying Cloud SQL deletion..."
    SQL_INSTANCES=$(gcloud sql instances list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$SQL_INSTANCES" ]]; then
        print_warning "Cloud SQL instances still exist: $SQL_INSTANCES"
    else
        print_status "Cloud SQL instances deleted"
    fi

    # Check VPC
    print_info "Verifying VPC deletion..."
    VPCS=$(gcloud compute networks list \
        --filter="name~${CLUSTER_NAME}" \
        --format="value(name)" \
        --project="$GCP_PROJECT" 2>/dev/null || echo "")

    if [[ -n "$VPCS" ]]; then
        print_warning "VPC still exists: $VPCS"
    else
        print_status "VPC deleted"
    fi
}

# Main destroy function
main() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}   MLOps Platform - GCP Destruction     ${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""

    # Check for --force flag
    FORCE=false
    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        FORCE=true
    fi

    print_warning "This will delete ALL resources including:"
    echo "  - GKE Cluster: ${CLUSTER_NAME}"
    echo "  - Cloud SQL instance"
    echo "  - GCS buckets"
    echo "  - Secret Manager secrets"
    echo "  - Artifact Registry"
    echo "  - VPC and all networking"
    echo ""

    if [[ "$FORCE" != true ]]; then
        read -p "Are you sure you want to destroy? (yes/no): " -r
        echo
        if [[ ! $REPLY == "yes" ]]; then
            print_info "Destroy cancelled"
            exit 0
        fi
    fi

    print_info "Cluster: ${CLUSTER_NAME}"
    print_info "Zone: ${GCP_ZONE}"
    print_info "Project: ${GCP_PROJECT}"
    echo ""

    # Run all cleanup phases
    phase1_kubernetes_cleanup

    # Run terraform destroy (retry once if it fails)
    if ! phase2_terraform_destroy; then
        print_warning "First terraform destroy failed, running additional cleanup..."
        phase3_gcp_cleanup
        print_info "Retrying terraform destroy..."
        phase2_terraform_destroy || true
    fi

    phase3_gcp_cleanup
    phase4_verification

    echo ""
    print_status "Destroy process complete!"
    print_info "Some resources may take a few minutes to fully delete."
    print_info "Run 'gcloud container clusters list' to verify."
    print_info "Run 'kubectl config delete-context ${CLUSTER_NAME}' to clean up local kubeconfig"
}

# Handle help
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--force]"
    echo ""
    echo "Destroys all MLOps platform GCP infrastructure with proper cleanup."
    echo ""
    echo "Options:"
    echo "  --force, -f   Skip confirmation prompt"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "This script handles common destroy issues:"
    echo "  - Kyverno webhooks blocking deletion"
    echo "  - KServe InferenceService finalizers"
    echo "  - Orphaned disks, forwarding rules, and backend services"
    echo "  - LoadBalancer services blocking IP release"
    exit 0
fi

main "$@"
