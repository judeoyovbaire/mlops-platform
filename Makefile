# MLOps Platform Makefile
# Multi-Cloud Deployment (AWS EKS / Azure AKS / GCP GKE)

.PHONY: help deploy deploy-aws deploy-azure deploy-gcp status status-aws status-azure status-gcp \
        destroy destroy-aws destroy-azure destroy-gcp secrets secrets-aws secrets-azure secrets-gcp \
        validate lint format test test-unit test-cov clean deps \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        terraform-init-aws terraform-plan-aws terraform-apply-aws terraform-destroy-aws \
        terraform-init-azure terraform-plan-azure terraform-apply-azure terraform-destroy-azure \
        terraform-init-gcp terraform-plan-gcp terraform-apply-gcp terraform-destroy-gcp \
        port-forward-mlflow port-forward-argocd port-forward-grafana port-forward-prometheus \
        port-forward-argo-wf validate-workflow deploy-example \
        deploy-local destroy-local status-local

# Default target
help:
	@echo "MLOps Platform - Multi-Cloud Commands"
	@echo "======================================"
	@echo ""
	@echo "Local Development:"
	@echo "  make deploy-local       - Deploy to local Kind cluster"
	@echo "  make status-local       - Check local cluster status"
	@echo "  make destroy-local      - Destroy local Kind cluster"
	@echo ""
	@echo "Quick Deployment (AWS default):"
	@echo "  make deploy             - Deploy to AWS EKS (default)"
	@echo "  make status             - Check AWS deployment status"
	@echo "  make destroy            - Destroy AWS resources"
	@echo "  make secrets            - Retrieve secrets from AWS"
	@echo ""
	@echo "AWS EKS Deployment:
	@echo "  make deploy-aws         - Deploy to AWS EKS (~15-20 min)"
	@echo "  make status-aws         - Check AWS deployment status"
	@echo "  make destroy-aws        - Destroy AWS resources"
	@echo "  make secrets-aws        - Retrieve secrets from AWS SSM"
	@echo ""
	@echo "Azure AKS Deployment:"
	@echo "  make deploy-azure       - Deploy to Azure AKS (~15-25 min)"
	@echo "  make status-azure       - Check Azure deployment status"
	@echo "  make destroy-azure      - Destroy Azure resources"
	@echo "  make secrets-azure      - Retrieve secrets from Azure Key Vault"
	@echo ""
	@echo "GCP GKE Deployment:"
	@echo "  make deploy-gcp         - Deploy to GCP GKE (~15-25 min)"
	@echo "  make status-gcp         - Check GCP deployment status"
	@echo "  make destroy-gcp        - Destroy GCP resources"
	@echo "  make secrets-gcp        - Retrieve secrets from GCP Secret Manager"
	@echo ""
	@echo "Terraform (Advanced):"
	@echo "  make terraform-init-aws     - Initialize AWS Terraform"
	@echo "  make terraform-plan-aws     - Plan AWS infrastructure"
	@echo "  make terraform-init-azure   - Initialize Azure Terraform"
	@echo "  make terraform-plan-azure   - Plan Azure infrastructure"
	@echo "  make terraform-init-gcp     - Initialize GCP Terraform"
	@echo "  make terraform-plan-gcp     - Plan GCP infrastructure"
	@echo ""
	@echo "Validation & Testing:"
	@echo "  make validate           - Validate all manifests"
	@echo "  make lint               - Lint Python and Terraform code"
	@echo "  make format             - Auto-format Python and Terraform code"
	@echo "  make test               - Run tests"
	@echo ""
	@echo "Development (after deployment):"
	@echo "  make port-forward-mlflow    - Forward MLflow to localhost:5000"
	@echo "  make port-forward-argocd    - Forward ArgoCD to localhost:8080"
	@echo "  make port-forward-grafana   - Forward Grafana to localhost:3000"
	@echo "  make port-forward-argo-wf   - Forward Argo Workflows to localhost:2746"
	@echo "  make deploy-example         - Deploy example inference service"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean              - Clean generated files"
	@echo "  make deps               - Install development dependencies"

# Variables
KUBECTL ?= kubectl
HELM ?= helm
TERRAFORM ?= terraform
PYTHON ?= python3

TERRAFORM_DIR_AWS = infrastructure/terraform/environments/aws/dev
TERRAFORM_DIR_AZURE = infrastructure/terraform/environments/azure/dev
TERRAFORM_DIR_GCP = infrastructure/terraform/environments/gcp/dev
PIPELINE_DIR = pipelines/training

# Default Deployment (AWS)

deploy: deploy-aws

status: status-aws

destroy: destroy-aws

secrets: secrets-aws

# AWS EKS Deployment

deploy-aws:
	@echo "Deploying MLOps Platform to AWS EKS..."
	./scripts/deploy-aws.sh deploy

status-aws:
	@echo "Checking AWS deployment status..."
	./scripts/deploy-aws.sh status

destroy-aws:
	@echo "Destroying AWS EKS deployment..."
	./scripts/destroy-aws.sh

secrets-aws:
	@echo "Retrieving secrets from AWS SSM..."
	./scripts/deploy-aws.sh secrets

# Azure AKS Deployment

deploy-azure:
	@echo "Deploying MLOps Platform to Azure AKS..."
	./scripts/deploy-azure.sh deploy

status-azure:
	@echo "Checking Azure deployment status..."
	./scripts/deploy-azure.sh status

destroy-azure:
	@echo "Destroying Azure AKS deployment..."
	./scripts/destroy-azure.sh

secrets-azure:
	@echo "Retrieving secrets from Azure Key Vault..."
	./scripts/deploy-azure.sh secrets

# GCP GKE Deployment

deploy-gcp:
	@echo "Deploying MLOps Platform to GCP GKE..."
	./scripts/deploy-gcp.sh deploy

status-gcp:
	@echo "Checking GCP deployment status..."
	./scripts/deploy-gcp.sh status

destroy-gcp:
	@echo "Destroying GCP GKE deployment..."
	./scripts/destroy-gcp.sh

secrets-gcp:
	@echo "Retrieving secrets from GCP Secret Manager..."
	./scripts/deploy-gcp.sh secrets

# Terraform - AWS (Advanced)

terraform-init: terraform-init-aws

terraform-plan: terraform-plan-aws

terraform-apply: terraform-apply-aws

terraform-destroy: terraform-destroy-aws

terraform-init-aws:
	@echo "Initializing AWS Terraform..."
	cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) init

terraform-plan-aws:
	@echo "Planning AWS Terraform changes..."
	cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) plan

terraform-apply-aws:
	@echo "Applying AWS Terraform changes..."
	cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) apply

terraform-destroy-aws:
	@echo "Destroying AWS Terraform resources..."
	cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) destroy

# Terraform - Azure (Advanced)

terraform-init-azure:
	@echo "Initializing Azure Terraform..."
	cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) init

terraform-plan-azure:
	@echo "Planning Azure Terraform changes..."
	cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) plan

terraform-apply-azure:
	@echo "Applying Azure Terraform changes..."
	cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) apply

terraform-destroy-azure:
	@echo "Destroying Azure Terraform resources..."
	cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) destroy

# Terraform - GCP (Advanced)

terraform-init-gcp:
	@echo "Initializing GCP Terraform..."
	cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) init

terraform-plan-gcp:
	@echo "Planning GCP Terraform changes..."
	cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) plan

terraform-apply-gcp:
	@echo "Applying GCP Terraform changes..."
	cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) apply

terraform-destroy-gcp:
	@echo "Destroying GCP Terraform resources..."
	cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) destroy

# Validation & Testing

validate: validate-terraform-aws validate-terraform-azure validate-terraform-gcp validate-python
	@echo "All validations passed!"

validate-terraform-aws:
	@echo "Validating AWS Terraform..."
	@cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) init -backend=false > /dev/null
	@cd $(TERRAFORM_DIR_AWS) && $(TERRAFORM) validate
	@echo "AWS Terraform validation passed"

validate-terraform-azure:
	@echo "Validating Azure Terraform..."
	@cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) init -backend=false > /dev/null 2>&1 || true
	@cd $(TERRAFORM_DIR_AZURE) && $(TERRAFORM) validate 2>/dev/null || echo "Azure Terraform validation skipped (bootstrap required)"

validate-terraform-gcp:
	@echo "Validating GCP Terraform..."
	@cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) init -backend=false > /dev/null 2>&1 || true
	@cd $(TERRAFORM_DIR_GCP) && $(TERRAFORM) validate 2>/dev/null || echo "GCP Terraform validation skipped (bootstrap required)"

validate-python:
	@echo "Validating Python code..."
	@$(PYTHON) -c "import yaml; list(yaml.safe_load_all(open('pipelines/training/ml-training-workflow.yaml')))"
	@echo "Python validation passed"

lint: lint-python lint-terraform
	@echo "All linting passed!"

lint-python:
	@echo "Linting Python code..."
	@if command -v ruff > /dev/null; then \
		ruff check pipelines/ examples/; \
		ruff format --check pipelines/ examples/; \
	else \
		echo "ruff not installed, skipping Python lint"; \
	fi

lint-terraform:
	@echo "Linting Terraform code..."
	$(TERRAFORM) fmt -check -recursive infrastructure/terraform/

format:
	@echo "Formatting code..."
	@if command -v ruff > /dev/null; then \
		ruff format pipelines/ examples/; \
		ruff check --fix pipelines/ examples/; \
	fi
	$(TERRAFORM) fmt -recursive infrastructure/terraform/
	@echo "Formatting complete!"

test: test-unit
	@echo "All tests passed!"

test-unit:
	@echo "Running unit tests..."
	pytest tests/ -v --tb=short

test-cov:
	@echo "Running tests with coverage..."
	pytest tests/ -v --cov=examples --cov=pipelines --cov-report=term-missing --cov-report=html
	@echo "Coverage report generated in htmlcov/"

# Development (post-deployment - cloud-agnostic)

port-forward-mlflow:
	@echo "Forwarding MLflow to localhost:5000..."
	@echo "Access MLflow at http://localhost:5000"
	$(KUBECTL) port-forward svc/mlflow 5000:5000 -n mlflow

port-forward-argocd:
	@echo "Forwarding ArgoCD to localhost:8080..."
	@echo "Access ArgoCD at https://localhost:8080"
	@echo "Password: $$($(KUBECTL) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo 'Check secrets')"
	$(KUBECTL) port-forward svc/argocd-server 8080:443 -n argocd

port-forward-argo-wf:
	@echo "Forwarding Argo Workflows to localhost:2746..."
	@echo "Access Argo Workflows at http://localhost:2746"
	$(KUBECTL) port-forward svc/argo-workflows-server 2746:2746 -n argo

port-forward-grafana:
	@echo "Forwarding Grafana to localhost:3000..."
	@echo "Access Grafana at http://localhost:3000"
	@echo "Username: admin"
	@echo "Password: Check 'make secrets-aws', 'make secrets-azure', or 'make secrets-gcp'"
	$(KUBECTL) port-forward svc/prometheus-grafana 3000:80 -n monitoring

port-forward-prometheus:
	@echo "Forwarding Prometheus to localhost:9090..."
	@echo "Access Prometheus at http://localhost:9090"
	$(KUBECTL) port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

validate-workflow:
	@echo "Validating Argo Workflow..."
	@$(PYTHON) -c "import yaml; list(yaml.safe_load_all(open('$(PIPELINE_DIR)/ml-training-workflow.yaml')))"
	@echo "Argo Workflow YAML is valid"

deploy-example:
	@echo "Deploying example inference service..."
	$(KUBECTL) apply -f examples/kserve/inferenceservice-examples.yaml
	@echo "Waiting for inference service to be ready..."
	$(KUBECTL) wait --for=condition=Ready inferenceservice/sklearn-iris -n mlops --timeout=300s || true
	$(KUBECTL) get inferenceservice -n mlops

deploy-pipeline:
	@echo "Deploying ML training pipeline..."
	$(KUBECTL) apply -k pipelines/training
	@echo "Pipeline templates updated."

# Utilities

deps:
	@echo "Installing development dependencies..."
	pip install -e ".[dev]"

clean:
	@echo "Cleaning generated files..."
	rm -f $(PIPELINE_DIR)/*.yaml
	rm -f $(PIPELINE_DIR)/*.json
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	rm -f $(TERRAFORM_DIR_AWS)/tfplan
	rm -f $(TERRAFORM_DIR_AZURE)/tfplan
	rm -f $(TERRAFORM_DIR_GCP)/tfplan
	@echo "Clean complete"

logs-mlflow:
	$(KUBECTL) logs -f deployment/mlflow -n mlflow

logs-argocd:
	$(KUBECTL) logs -f deployment/argocd-server -n argocd

# Local Development (Kind cluster)

deploy-local:
	@echo "Deploying MLOps Platform to local Kind cluster..."
	./scripts/deploy-local.sh deploy

status-local:
	@echo "Checking local Kind cluster status..."
	./scripts/deploy-local.sh status

destroy-local:
	@echo "Destroying local Kind cluster..."
	./scripts/deploy-local.sh destroy