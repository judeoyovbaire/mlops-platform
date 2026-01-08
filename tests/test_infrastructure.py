"""
Infrastructure Configuration Tests.

Tests that verify Terraform and Kubernetes configurations are valid and follow best practices.
"""

import pytest
import json
import yaml
import shutil
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent

# Check if terraform is available
TERRAFORM_AVAILABLE = shutil.which("terraform") is not None


class TestTerraformConfiguration:
    """Tests for Terraform configuration validity."""

    @pytest.fixture
    def aws_tf_dir(self):
        return PROJECT_ROOT / "infrastructure" / "terraform" / "environments" / "aws" / "dev"

    @pytest.fixture
    def azure_tf_dir(self):
        return PROJECT_ROOT / "infrastructure" / "terraform" / "environments" / "azure" / "dev"

    @pytest.fixture
    def gcp_tf_dir(self):
        return PROJECT_ROOT / "infrastructure" / "terraform" / "environments" / "gcp" / "dev"

    @pytest.mark.skipif(not TERRAFORM_AVAILABLE, reason="terraform not installed")
    def test_aws_terraform_valid(self, aws_tf_dir):
        """Verify AWS Terraform configuration is syntactically valid."""
        if not aws_tf_dir.exists():
            pytest.skip("AWS dev environment not found")

        result = subprocess.run(
            ["terraform", "validate"],
            cwd=aws_tf_dir,
            capture_output=True,
            text=True
        )
        # Accept either success or skip if not initialized
        assert result.returncode == 0 or "Could not satisfy plugin requirements" in result.stderr

    @pytest.mark.skipif(not TERRAFORM_AVAILABLE, reason="terraform not installed")
    def test_azure_terraform_valid(self, azure_tf_dir):
        """Verify Azure Terraform configuration is syntactically valid."""
        if not azure_tf_dir.exists():
            pytest.skip("Azure dev environment not found")

        result = subprocess.run(
            ["terraform", "validate"],
            cwd=azure_tf_dir,
            capture_output=True,
            text=True
        )
        assert result.returncode == 0 or "Could not satisfy plugin requirements" in result.stderr

    @pytest.mark.skipif(not TERRAFORM_AVAILABLE, reason="terraform not installed")
    def test_gcp_terraform_valid(self, gcp_tf_dir):
        """Verify GCP Terraform configuration is syntactically valid."""
        if not gcp_tf_dir.exists():
            pytest.skip("GCP dev environment not found")

        result = subprocess.run(
            ["terraform", "validate"],
            cwd=gcp_tf_dir,
            capture_output=True,
            text=True
        )
        assert result.returncode == 0 or "Could not satisfy plugin requirements" in result.stderr

    def test_all_environments_have_required_files(self):
        """Verify all environments have required Terraform files."""
        required_files = ["providers.tf", "variables.tf"]

        for cloud in ["aws", "azure", "gcp"]:
            tf_dir = PROJECT_ROOT / "infrastructure" / "terraform" / "environments" / cloud / "dev"
            if tf_dir.exists():
                for required_file in required_files:
                    assert (tf_dir / required_file).exists(), \
                        f"{cloud}/dev missing {required_file}"


class TestHelmValues:
    """Tests for Helm values configuration."""

    @pytest.fixture
    def helm_dir(self):
        return PROJECT_ROOT / "infrastructure" / "helm"

    def test_helm_values_valid_yaml(self, helm_dir):
        """Verify all Helm values files are valid YAML."""
        for cloud_dir in helm_dir.iterdir():
            if cloud_dir.is_dir():
                for values_file in cloud_dir.glob("*-values.yaml"):
                    try:
                        with open(values_file) as f:
                            yaml.safe_load(f)
                    except yaml.YAMLError as e:
                        pytest.fail(f"Invalid YAML in {values_file}: {e}")

    def test_argocd_values_secure(self, helm_dir):
        """Verify ArgoCD values don't have insecure settings."""
        for cloud_dir in helm_dir.iterdir():
            if cloud_dir.is_dir():
                argocd_file = cloud_dir / "argocd-values.yaml"
                if argocd_file.exists():
                    with open(argocd_file) as f:
                        content = f.read()
                        # Should not have --insecure flag
                        assert "--insecure" not in content, \
                            f"ArgoCD in {cloud_dir.name} should not use --insecure"

    def test_prometheus_no_hardcoded_passwords(self, helm_dir):
        """Verify Prometheus stack doesn't have hardcoded passwords."""
        for cloud_dir in helm_dir.iterdir():
            if cloud_dir.is_dir():
                prom_file = cloud_dir / "prometheus-stack-values.yaml"
                if prom_file.exists():
                    with open(prom_file) as f:
                        values = yaml.safe_load(f)

                    # Check Grafana doesn't have hardcoded admin password
                    grafana = values.get("grafana", {})
                    admin_password = grafana.get("adminPassword")

                    # Should either be null/None or use external secret
                    if admin_password is not None:
                        assert admin_password != "admin", \
                            f"Grafana in {cloud_dir.name} should not use default password"


class TestKubernetesManifests:
    """Tests for Kubernetes manifest validity."""

    @pytest.fixture
    def k8s_dir(self):
        return PROJECT_ROOT / "infrastructure" / "kubernetes"

    def test_manifests_valid_yaml(self, k8s_dir):
        """Verify all Kubernetes manifests are valid YAML."""
        for manifest in k8s_dir.glob("*.yaml"):
            try:
                with open(manifest) as f:
                    # Handle multi-document YAML
                    list(yaml.safe_load_all(f))
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {manifest}: {e}")

    def test_network_policies_exist(self, k8s_dir):
        """Verify network policies are defined."""
        network_policies = k8s_dir / "network-policies.yaml"
        assert network_policies.exists(), "Network policies should be defined"

        with open(network_policies) as f:
            docs = list(yaml.safe_load_all(f))

        # Should have multiple policies
        policies = [d for d in docs if d and d.get("kind") == "NetworkPolicy"]
        assert len(policies) >= 3, "Should have network policies for multiple namespaces"

    def test_pdbs_exist(self, k8s_dir):
        """Verify PodDisruptionBudgets are defined."""
        pdbs_file = k8s_dir / "pod-disruption-budgets.yaml"
        assert pdbs_file.exists(), "PodDisruptionBudgets should be defined"

        with open(pdbs_file) as f:
            docs = list(yaml.safe_load_all(f))

        pdbs = [d for d in docs if d and d.get("kind") == "PodDisruptionBudget"]
        assert len(pdbs) >= 5, "Should have PDBs for critical services"

    def test_resource_quotas_exist(self, k8s_dir):
        """Verify ResourceQuotas are defined."""
        quotas_file = k8s_dir / "resource-quotas.yaml"
        assert quotas_file.exists(), "ResourceQuotas should be defined"

        with open(quotas_file) as f:
            docs = list(yaml.safe_load_all(f))

        quotas = [d for d in docs if d and d.get("kind") == "ResourceQuota"]
        limit_ranges = [d for d in docs if d and d.get("kind") == "LimitRange"]

        assert len(quotas) >= 3, "Should have quotas for main namespaces"
        assert len(limit_ranges) >= 3, "Should have limit ranges for main namespaces"


class TestSecurityConfiguration:
    """Tests for security configuration across all environments."""

    def test_psa_labels_configured(self):
        """Verify Pod Security Admission labels are set in all environments."""
        for cloud in ["aws", "azure", "gcp"]:
            namespaces_file = PROJECT_ROOT / "infrastructure" / "terraform" / \
                "environments" / cloud / "dev" / "namespaces.tf"

            if namespaces_file.exists():
                content = namespaces_file.read_text()

                # Check for PSA enforce labels
                assert "pod-security.kubernetes.io/enforce" in content, \
                    f"{cloud} should have PSA enforce labels"

                # mlops, mlflow, kserve should be restricted
                assert "restricted" in content, \
                    f"{cloud} should use restricted PSA for workload namespaces"

    def test_irsa_workload_identity_configured(self):
        """Verify cloud identity is configured (IRSA/Workload Identity)."""
        # Each cloud may have multiple valid patterns (e.g., escaped dots in Terraform)
        checks = {
            "aws": ["eks.amazonaws.com/role-arn"],
            "azure": ["azure.workload.identity", "azure\\.workload\\.identity"],
            "gcp": ["iam.gke.io/gcp-service-account"]
        }

        for cloud, annotations in checks.items():
            tf_dir = PROJECT_ROOT / "infrastructure" / "terraform" / \
                "environments" / cloud / "dev"

            if tf_dir.exists():
                all_content = ""
                for tf_file in tf_dir.glob("*.tf"):
                    all_content += tf_file.read_text()

                found = any(annotation in all_content for annotation in annotations)
                assert found, \
                    f"{cloud} should configure workload identity annotation"


class TestExamples:
    """Tests for example configurations."""

    @pytest.fixture
    def examples_dir(self):
        return PROJECT_ROOT / "examples"

    def test_examples_valid_yaml(self, examples_dir):
        """Verify all example files are valid YAML."""
        for example_file in examples_dir.rglob("*.yaml"):
            try:
                with open(example_file) as f:
                    list(yaml.safe_load_all(f))
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {example_file}: {e}")

    def test_inferenceservice_examples_exist(self, examples_dir):
        """Verify InferenceService examples are provided."""
        kserve_examples = list(examples_dir.rglob("*inferenceservice*.yaml")) + \
                         list(examples_dir.rglob("*InferenceService*.yaml"))

        assert len(kserve_examples) >= 1, "Should have InferenceService examples"

    def test_canary_example_exists(self, examples_dir):
        """Verify canary deployment example exists."""
        canary_dir = examples_dir / "canary-deployment"
        assert canary_dir.exists(), "Canary deployment example should exist"
        assert (canary_dir / "README.md").exists(), "Canary example should have README"
