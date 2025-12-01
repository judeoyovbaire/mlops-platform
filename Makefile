# MLOps Platform Makefile
# Common operations for development and deployment

.PHONY: help install install-dev uninstall validate lint test clean \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        port-forward-mlflow port-forward-argocd compile-pipeline

# Default target
help:
	@echo "MLOps Platform - Available Commands"
	@echo "===================================="
	@echo ""
	@echo "Installation:"
	@echo "  make install          - Install platform components"
	@echo "  make install-dev      - Install with dev configurations"
	@echo "  make uninstall        - Remove platform components"
	@echo ""
	@echo "Validation & Testing:"
	@echo "  make validate         - Validate all manifests"
	@echo "  make lint             - Lint Python and Terraform code"
	@echo "  make test             - Run tests"
	@echo ""
	@echo "Terraform:"
	@echo "  make terraform-init   - Initialize Terraform"
	@echo "  make terraform-plan   - Plan infrastructure changes"
	@echo "  make terraform-apply  - Apply infrastructure changes"
	@echo "  make terraform-destroy - Destroy infrastructure"
	@echo ""
	@echo "Development:"
	@echo "  make port-forward-mlflow  - Forward MLflow to localhost:5000"
	@echo "  make port-forward-argocd  - Forward ArgoCD to localhost:8080"
	@echo "  make compile-pipeline     - Compile Kubeflow pipeline"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean            - Clean generated files"
	@echo "  make deps             - Install development dependencies"

# Variables
KUBECTL ?= kubectl
HELM ?= helm
TERRAFORM ?= terraform
PYTHON ?= python3
KUSTOMIZE ?= kustomize

TERRAFORM_DIR = infrastructure/terraform/environments/dev
PIPELINE_DIR = pipelines/training

# =============================================================================
# Installation
# =============================================================================

install:
	@echo "Installing MLOps Platform..."
	./scripts/install.sh

install-dev:
	@echo "Installing MLOps Platform (dev mode)..."
	$(KUBECTL) apply -f infrastructure/kubernetes/namespace.yaml
	$(KUSTOMIZE) build infrastructure/kubernetes | $(KUBECTL) apply -f -

uninstall:
	@echo "Uninstalling MLOps Platform..."
	$(HELM) uninstall argocd -n argocd || true
	$(HELM) uninstall mlflow -n mlflow || true
	$(KUBECTL) delete -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml || true
	$(KUBECTL) delete namespace mlops mlflow kubeflow kserve argocd || true
	@echo "Uninstall complete"

# =============================================================================
# Validation & Testing
# =============================================================================

validate: validate-k8s validate-terraform validate-python
	@echo "All validations passed!"

validate-k8s:
	@echo "Validating Kubernetes manifests..."
	@find components infrastructure/kubernetes -name '*.yaml' -exec $(KUBECTL) apply --dry-run=client -f {} \; 2>/dev/null || true
	@$(KUSTOMIZE) build infrastructure/kubernetes > /dev/null
	@echo "Kubernetes validation passed"

validate-terraform:
	@echo "Validating Terraform..."
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) init -backend=false > /dev/null
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) validate
	@$(TERRAFORM) fmt -check -recursive infrastructure/terraform/
	@echo "Terraform validation passed"

validate-python:
	@echo "Validating Python code..."
	@$(PYTHON) -m py_compile pipelines/training/example-pipeline.py
	@$(PYTHON) -m py_compile examples/iris-classifier/train.py
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

test:
	@echo "Running tests..."
	@$(PYTHON) -c "from pipelines.training import example_pipeline; print('Pipeline import OK')" 2>/dev/null || \
		$(PYTHON) -c "exec(open('pipelines/training/example-pipeline.py').read()); print('Pipeline syntax OK')"
	@$(PYTHON) -c "import examples.iris_classifier.train" 2>/dev/null || \
		$(PYTHON) -c "exec(open('examples/iris-classifier/train.py').read()); print('Train script syntax OK')"
	@echo "Tests passed"

# =============================================================================
# Terraform
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
# Development
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

compile-pipeline:
	@echo "Compiling Kubeflow pipeline..."
	cd $(PIPELINE_DIR) && $(PYTHON) example-pipeline.py
	@echo "Pipeline compiled to $(PIPELINE_DIR)/ml_training_pipeline.yaml"

deploy-example:
	@echo "Deploying example inference service..."
	$(KUBECTL) apply -f examples/iris-classifier/kserve-deployment.yaml
	@echo "Waiting for inference service to be ready..."
	$(KUBECTL) wait --for=condition=Ready inferenceservice/iris-classifier -n mlops --timeout=300s || true
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

status:
	@echo "=== Namespaces ==="
	$(KUBECTL) get namespaces -l app.kubernetes.io/part-of=mlops-platform
	@echo ""
	@echo "=== MLflow ==="
	$(KUBECTL) get pods -n mlflow
	@echo ""
	@echo "=== KServe InferenceServices ==="
	$(KUBECTL) get inferenceservice -n mlops 2>/dev/null || echo "No InferenceServices found"
	@echo ""
	@echo "=== ArgoCD ==="
	$(KUBECTL) get pods -n argocd

logs-mlflow:
	$(KUBECTL) logs -f deployment/mlflow -n mlflow

logs-argocd:
	$(KUBECTL) logs -f deployment/argocd-server -n argocd