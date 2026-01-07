#!/bin/bash
set -euo pipefail

# MLOps Platform - GCP GKE Destruction
# Safely destroys all GCP resources with proper cleanup order

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

echo -e "${RED}========================================${NC}"
echo -e "${RED}   MLOps Platform - GCP Destruction     ${NC}"
echo -e "${RED}========================================${NC}"
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

# Get configuration
CLUSTER_NAME=${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}
GCP_REGION=${GCP_REGION:-$DEFAULT_GCP_REGION}
GCP_ZONE=${GCP_ZONE:-$DEFAULT_GCP_ZONE}
GCP_PROJECT=${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}

echo -e "${YELLOW}WARNING: This will destroy ALL resources:${NC}"
echo "  - GKE Cluster: ${CLUSTER_NAME}"
echo "  - Cloud SQL instance"
echo "  - GCS buckets"
echo "  - Secret Manager secrets"
echo "  - Artifact Registry"
echo "  - VPC and all networking"
echo ""

# Confirmation
read -p "Type 'destroy' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
    print_info "Destruction cancelled"
    exit 0
fi

echo ""

# Phase 1: Kubernetes cleanup
phase1_kubernetes_cleanup() {
    echo -e "${BLUE}Phase 1: Kubernetes Resource Cleanup${NC}"

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
    echo -e "${BLUE}Phase 2: Terraform Destroy${NC}"

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
    terraform destroy -auto-approve || {
        print_warning "Terraform destroy encountered errors - continuing with cleanup"
    }

    print_status "Terraform destroy complete"
}

# Phase 3: GCP orphaned resources cleanup
phase3_gcp_cleanup() {
    echo ""
    echo -e "${BLUE}Phase 3: GCP Orphaned Resources Cleanup${NC}"

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
    echo -e "${BLUE}Phase 4: Verification${NC}"

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

# Main execution
main() {
    phase1_kubernetes_cleanup
    phase2_terraform_destroy
    phase3_gcp_cleanup
    phase4_verification

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Destruction Complete                  ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    print_info "Some resources may take a few minutes to fully delete."
    print_info "Run 'gcloud container clusters list' to verify."
}

main
