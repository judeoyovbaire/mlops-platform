# MLOps Platform Makefile
# AWS EKS Deployment

.PHONY: help deploy status destroy validate lint test test-unit test-cov clean deps \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        port-forward-mlflow port-forward-argocd port-forward-grafana port-forward-prometheus \
        compile-pipeline deploy-example bootstrap

# Default target
help:
	@echo "MLOps Platform - Available Commands"
	@echo "===================================="
	@echo ""
	@echo "AWS EKS Deployment:"
	@echo "  make deploy           - Deploy to AWS EKS (~15-20 min)"
	@echo "  make status           - Check deployment status"
	@echo "  make destroy          - Destroy AWS resources"
	@echo ""
	@echo "Terraform (Advanced):"
	@echo "  make terraform-init   - Initialize Terraform"
	@echo "  make terraform-plan   - Plan infrastructure changes"
	@echo "  make terraform-apply  - Apply infrastructure changes"
	@echo "  make terraform-destroy - Destroy infrastructure"
	@echo ""
	@echo "Validation & Testing:"
	@echo "  make validate         - Validate all manifests"
	@echo "  make lint             - Lint Python and Terraform code"
	@echo "  make test             - Run tests"
	@echo ""
	@echo "Development (after deployment):"
	@echo "  make port-forward-mlflow  - Forward MLflow to localhost:5000"
	@echo "  make port-forward-argocd  - Forward ArgoCD to localhost:8080"
	@echo "  make compile-pipeline     - Compile Kubeflow pipeline"
	@echo "  make deploy-example       - Deploy example inference service"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean            - Clean generated files"
	@echo "  make deps             - Install development dependencies"

# Variables
KUBECTL ?= kubectl
HELM ?= helm
TERRAFORM ?= terraform
PYTHON ?= python3

TERRAFORM_DIR = infrastructure/terraform/environments/dev
PIPELINE_DIR = pipelines/training

# =============================================================================
# AWS EKS Deployment
# =============================================================================

deploy:
	@echo "Deploying MLOps Platform to AWS EKS..."
	./scripts/deploy-aws.sh deploy

status:
	@echo "Checking AWS deployment status..."
	./scripts/deploy-aws.sh status

destroy:
	@echo "Destroying AWS EKS deployment..."
	./scripts/deploy-aws.sh destroy

# =============================================================================
# Terraform (Advanced)
# =============================================================================

terraform-init:
	@echo "Initializing Terraform..."
	cd $(TERRAFORM_DIR) && $(TERRAFORM) init

terraform-plan:
	@echo "Planning Terraform changes..."
	cd $(TERRAFORM_DIR) && $(TERRAFORM) plan

terraform-apply:
	@echo "Applying Terraform changes..."
	cd $(TERRAFORM_DIR) && $(TERRAFORM) apply

terraform-destroy:
	@echo "Destroying Terraform resources..."
	cd $(TERRAFORM_DIR) && $(TERRAFORM) destroy

# =============================================================================
# Validation & Testing
# =============================================================================

validate: validate-terraform validate-python
	@echo "All validations passed!"

validate-terraform:
	@echo "Validating Terraform..."
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) init -backend=false > /dev/null
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) validate
	@$(TERRAFORM) fmt -check -recursive infrastructure/terraform/
	@echo "Terraform validation passed"

validate-python:
	@echo "Validating Python code..."
	@$(PYTHON) -m py_compile pipelines/training/example-pipeline.py
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

test: test-unit
	@echo "All tests passed!"

test-unit:
	@echo "Running unit tests..."
	pytest tests/ -v --tb=short

test-cov:
	@echo "Running tests with coverage..."
	pytest tests/ -v --cov=examples --cov=pipelines --cov-report=term-missing --cov-report=html
	@echo "Coverage report generated in htmlcov/"

# =============================================================================
# Development (post-deployment)
# =============================================================================

port-forward-mlflow:
	@echo "Forwarding MLflow to localhost:5000..."
	@echo "Access MLflow at http://localhost:5000"
	$(KUBECTL) port-forward svc/mlflow 5000:5000 -n mlflow

port-forward-argocd:
	@echo "Forwarding ArgoCD to localhost:8080..."
	@echo "Access ArgoCD at https://localhost:8080"
	@echo "Password: $$($(KUBECTL) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	$(KUBECTL) port-forward svc/argocd-server 8080:443 -n argocd

port-forward-kubeflow:
	@echo "Forwarding Kubeflow to localhost:8081..."
	@echo "Access Kubeflow at http://localhost:8081"
	$(KUBECTL) port-forward svc/ml-pipeline-ui 8081:80 -n kubeflow

port-forward-grafana:
	@echo "Forwarding Grafana to localhost:3000..."
	@echo "Access Grafana at http://localhost:3000"
	@echo "Username: admin"
	@echo "Password: Retrieve with 'aws ssm get-parameter --name /mlops-platform-dev/grafana/admin-password --with-decryption'"
	$(KUBECTL) port-forward svc/prometheus-grafana 3000:80 -n monitoring

port-forward-prometheus:
	@echo "Forwarding Prometheus to localhost:9090..."
	@echo "Access Prometheus at http://localhost:9090"
	$(KUBECTL) port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

compile-pipeline:
	@echo "Compiling Kubeflow pipeline..."
	cd $(PIPELINE_DIR) && $(PYTHON) example-pipeline.py
	@echo "Pipeline compiled to $(PIPELINE_DIR)/ml_training_pipeline.yaml"

deploy-example:
	@echo "Deploying example inference service..."
	$(KUBECTL) apply -f components/kserve/inferenceservice-examples.yaml
	@echo "Waiting for inference service to be ready..."
	$(KUBECTL) wait --for=condition=Ready inferenceservice/sklearn-iris -n mlops --timeout=300s || true
	$(KUBECTL) get inferenceservice -n mlops

# =============================================================================
# Utilities
# =============================================================================

deps:
	@echo "Installing development dependencies..."
	pip install ruff mypy pytest kfp mlflow pandas scikit-learn boto3

clean:
	@echo "Cleaning generated files..."
	rm -f $(PIPELINE_DIR)/*.yaml
	rm -f $(PIPELINE_DIR)/*.json
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	@echo "Clean complete"

logs-mlflow:
	$(KUBECTL) logs -f deployment/mlflow -n mlflow

logs-argocd:
	$(KUBECTL) logs -f deployment/argocd-server -n argocd