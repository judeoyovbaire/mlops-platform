#!/bin/bash
# =============================================================================
# MLOps Platform Cost Report Generator
# =============================================================================
# Generates cost reports for AWS, Azure, or GCP deployments
# Usage: ./cost-report-generator.sh [aws|azure|gcp] [--days N]

set -euo pipefail

CLOUD_PROVIDER="${1:-aws}"
DAYS="${2:-30}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/cost-reports}"
REPORT_DATE=$(date +%Y-%m-%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

mkdir -p "$OUTPUT_DIR"

# =============================================================================
# AWS Cost Report
# =============================================================================
generate_aws_report() {
    log_info "Generating AWS cost report for the last $DAYS days..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    START_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-$DAYS days" +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)

    REPORT_FILE="$OUTPUT_DIR/aws-cost-report-$REPORT_DATE.json"

    log_info "Fetching cost data from $START_DATE to $END_DATE..."

    # Get cost and usage data
    aws ce get-cost-and-usage \
        --time-period Start=$START_DATE,End=$END_DATE \
        --granularity DAILY \
        --metrics "BlendedCost" "UnblendedCost" "UsageQuantity" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "$REPORT_FILE" 2>/dev/null || {
        log_warn "Could not fetch detailed cost data. Generating summary..."

        # Fallback to account summary
        aws ce get-cost-and-usage \
            --time-period Start=$START_DATE,End=$END_DATE \
            --granularity MONTHLY \
            --metrics "BlendedCost" \
            --output json > "$REPORT_FILE" 2>/dev/null || {
            log_error "Failed to generate AWS cost report"
            return 1
        }
    }

    # Generate EKS-specific costs
    log_info "Fetching EKS cluster costs..."
    EKS_REPORT="$OUTPUT_DIR/aws-eks-costs-$REPORT_DATE.json"

    aws ce get-cost-and-usage \
        --time-period Start=$START_DATE,End=$END_DATE \
        --granularity MONTHLY \
        --metrics "BlendedCost" \
        --filter '{
            "Or": [
                {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Kubernetes Service"]}},
                {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Elastic Compute Cloud - Compute"]}},
                {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Relational Database Service"]}},
                {"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Simple Storage Service"]}}
            ]
        }' \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "$EKS_REPORT" 2>/dev/null || log_warn "Could not fetch EKS-specific costs"

    log_info "AWS cost report generated: $REPORT_FILE"

    # Print summary
    echo ""
    echo "=== AWS Cost Summary ==="
    if command -v jq &> /dev/null; then
        jq -r '.ResultsByTime[] | "Date: \(.TimePeriod.Start) - Total: $\(.Total.BlendedCost.Amount)"' "$REPORT_FILE" 2>/dev/null || cat "$REPORT_FILE"
    else
        cat "$REPORT_FILE"
    fi
}

# =============================================================================
# Azure Cost Report
# =============================================================================
generate_azure_report() {
    log_info "Generating Azure cost report for the last $DAYS days..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Please install it first."
        exit 1
    fi

    START_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-$DAYS days" +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)

    REPORT_FILE="$OUTPUT_DIR/azure-cost-report-$REPORT_DATE.json"

    log_info "Fetching cost data from $START_DATE to $END_DATE..."

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)

    if [ -z "$SUBSCRIPTION_ID" ]; then
        log_error "Not logged into Azure. Run 'az login' first."
        exit 1
    }

    # Query cost management API
    az consumption usage list \
        --start-date "$START_DATE" \
        --end-date "$END_DATE" \
        --output json > "$REPORT_FILE" 2>/dev/null || {
        log_warn "Could not fetch detailed usage. Trying budget summary..."

        # Fallback to budget info
        az consumption budget list --output json > "$REPORT_FILE" 2>/dev/null || {
            log_error "Failed to generate Azure cost report"
            return 1
        }
    }

    # Get AKS-specific costs via resource tags
    log_info "Fetching AKS resource costs..."
    AKS_REPORT="$OUTPUT_DIR/azure-aks-costs-$REPORT_DATE.json"

    az resource list \
        --tag Environment=prod \
        --query "[?contains(type, 'Microsoft.ContainerService') || contains(type, 'Microsoft.DBforPostgreSQL') || contains(type, 'Microsoft.Storage')]" \
        --output json > "$AKS_REPORT" 2>/dev/null || log_warn "Could not fetch AKS-specific resources"

    log_info "Azure cost report generated: $REPORT_FILE"
}

# =============================================================================
# GCP Cost Report
# =============================================================================
generate_gcp_report() {
    log_info "Generating GCP cost report for the last $DAYS days..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install it first."
        exit 1
    }

    START_DATE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-$DAYS days" +%Y-%m-%d)
    END_DATE=$(date +%Y-%m-%d)

    REPORT_FILE="$OUTPUT_DIR/gcp-cost-report-$REPORT_DATE.json"
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

    if [ -z "$PROJECT_ID" ]; then
        log_error "No GCP project set. Run 'gcloud config set project PROJECT_ID' first."
        exit 1
    }

    log_info "Project: $PROJECT_ID"
    log_info "Fetching cost data from $START_DATE to $END_DATE..."

    # Note: Billing export to BigQuery is recommended for detailed cost analysis
    # This uses the basic billing API
    BILLING_ACCOUNT=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null | cut -d'/' -f2)

    if [ -n "$BILLING_ACCOUNT" ]; then
        log_info "Billing Account: $BILLING_ACCOUNT"

        # Get GKE clusters for cost attribution
        GKE_REPORT="$OUTPUT_DIR/gcp-gke-resources-$REPORT_DATE.json"
        gcloud container clusters list --format=json > "$GKE_REPORT" 2>/dev/null

        # Get Cloud SQL instances
        SQL_REPORT="$OUTPUT_DIR/gcp-sql-resources-$REPORT_DATE.json"
        gcloud sql instances list --format=json > "$SQL_REPORT" 2>/dev/null

        # Get GCS buckets
        GCS_REPORT="$OUTPUT_DIR/gcp-storage-resources-$REPORT_DATE.json"
        gsutil ls -L -b 2>/dev/null | head -50 > "$GCS_REPORT" || true

        log_info "GCP resource reports generated in $OUTPUT_DIR"
    else
        log_warn "Could not determine billing account"
    }

    # Create summary file
    cat > "$REPORT_FILE" << EOF
{
    "project_id": "$PROJECT_ID",
    "report_date": "$REPORT_DATE",
    "period": {
        "start": "$START_DATE",
        "end": "$END_DATE"
    },
    "note": "For detailed cost analysis, enable BigQuery billing export"
}
EOF

    log_info "GCP cost report generated: $REPORT_FILE"
}

# =============================================================================
# Kubernetes Resource Cost Estimation
# =============================================================================
estimate_k8s_costs() {
    log_info "Estimating Kubernetes resource costs..."

    K8S_REPORT="$OUTPUT_DIR/k8s-resource-costs-$REPORT_DATE.json"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl not found. Skipping K8s resource estimation."
        return
    }

    # Get node resources
    kubectl get nodes -o json 2>/dev/null | jq '{
        nodes: [.items[] | {
            name: .metadata.name,
            cpu: .status.capacity.cpu,
            memory: .status.capacity.memory,
            instance_type: .metadata.labels["node.kubernetes.io/instance-type"]
        }]
    }' > "$K8S_REPORT" 2>/dev/null || log_warn "Could not fetch node information"

    # Get pod resource usage by namespace
    NAMESPACE_REPORT="$OUTPUT_DIR/k8s-namespace-costs-$REPORT_DATE.json"

    kubectl get pods --all-namespaces -o json 2>/dev/null | jq '{
        namespaces: [.items | group_by(.metadata.namespace)[] | {
            namespace: .[0].metadata.namespace,
            pod_count: length,
            containers: [.[].spec.containers[].resources // {}]
        }]
    }' > "$NAMESPACE_REPORT" 2>/dev/null || log_warn "Could not fetch pod resources"

    log_info "Kubernetes resource reports generated"
}

# =============================================================================
# Generate Recommendations
# =============================================================================
generate_recommendations() {
    log_info "Generating cost optimization recommendations..."

    RECOMMENDATIONS_FILE="$OUTPUT_DIR/recommendations-$REPORT_DATE.md"

    cat > "$RECOMMENDATIONS_FILE" << 'EOF'
# MLOps Platform Cost Optimization Recommendations

## General Recommendations

### 1. Right-size Node Pools
- Review node pool sizes monthly
- Use cluster autoscaler with appropriate min/max settings
- Consider using smaller instance types for dev/staging

### 2. Use Spot/Preemptible Instances
- Training workloads: Use Spot instances (up to 90% savings)
- GPU workloads: Mix of Spot and On-Demand for fault tolerance
- Inference: On-Demand for production, Spot for development

### 3. Storage Optimization
- Enable lifecycle policies for artifact storage
- Use appropriate storage classes (standard vs premium)
- Clean up orphaned PVCs regularly

### 4. Inference Endpoint Optimization
- Scale down unused inference services
- Use autoscaling based on traffic patterns
- Consider serverless inference for low-traffic models

### 5. Database Optimization
- Right-size RDS/Cloud SQL instances
- Enable auto-pause for development databases
- Use reserved instances for production (up to 60% savings)

## Cloud-Specific Recommendations

### AWS
- Use Savings Plans for consistent workloads
- Enable S3 Intelligent-Tiering for artifacts
- Use Graviton instances where possible

### Azure
- Use Reserved Instances for AKS nodes
- Enable Azure Hybrid Benefit if applicable
- Use Azure Spot VMs for training jobs

### GCP
- Use Committed Use Discounts
- Enable Recommender API for right-sizing
- Use Preemptible VMs for batch workloads

## Monitoring Actions
- Set up billing alerts at 50%, 80%, 100% of budget
- Review cost reports weekly
- Tag all resources for cost attribution
EOF

    log_info "Recommendations saved to: $RECOMMENDATIONS_FILE"
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo "=============================================="
    echo "MLOps Platform Cost Report Generator"
    echo "=============================================="
    echo "Cloud Provider: $CLOUD_PROVIDER"
    echo "Report Period: Last $DAYS days"
    echo "Output Directory: $OUTPUT_DIR"
    echo ""

    case "$CLOUD_PROVIDER" in
        aws)
            generate_aws_report
            ;;
        azure)
            generate_azure_report
            ;;
        gcp)
            generate_gcp_report
            ;;
        *)
            log_error "Unknown cloud provider: $CLOUD_PROVIDER"
            echo "Usage: $0 [aws|azure|gcp] [--days N]"
            exit 1
            ;;
    esac

    estimate_k8s_costs
    generate_recommendations

    echo ""
    echo "=============================================="
    echo "Cost reports generated in: $OUTPUT_DIR"
    echo "=============================================="
    ls -la "$OUTPUT_DIR"
}

main "$@"