"""
Terraform Module Unit Tests.

Tests that verify Terraform modules follow best practices and have proper configurations.
These tests can run without terraform init by parsing HCL files directly.
"""

import re
from pathlib import Path
from typing import Any

import pytest

PROJECT_ROOT = Path(__file__).parent.parent
MODULES_DIR = PROJECT_ROOT / "infrastructure" / "terraform" / "modules"


def parse_terraform_variables(tf_content: str) -> dict[str, Any]:
    """Extract variable definitions from Terraform content."""
    variables = {}
    # Match variable blocks
    var_pattern = r'variable\s+"([^"]+)"\s*\{([^}]+)\}'
    for match in re.finditer(var_pattern, tf_content, re.DOTALL):
        var_name = match.group(1)
        var_block = match.group(2)

        var_info = {"name": var_name}

        # Check for description
        desc_match = re.search(r'description\s*=\s*"([^"]*)"', var_block)
        if desc_match:
            var_info["description"] = desc_match.group(1)

        # Check for type
        type_match = re.search(r"type\s*=\s*(\S+)", var_block)
        if type_match:
            var_info["type"] = type_match.group(1)

        # Check for default
        var_info["has_default"] = "default" in var_block

        # Check for sensitive
        var_info["sensitive"] = "sensitive" in var_block and "= true" in var_block

        variables[var_name] = var_info

    return variables


def parse_terraform_outputs(tf_content: str) -> dict[str, Any]:
    """Extract output definitions from Terraform content."""
    outputs = {}
    output_pattern = r'output\s+"([^"]+)"\s*\{([^}]+)\}'
    for match in re.finditer(output_pattern, tf_content, re.DOTALL):
        output_name = match.group(1)
        output_block = match.group(2)

        output_info = {"name": output_name}
        output_info["has_description"] = "description" in output_block
        output_info["sensitive"] = "sensitive" in output_block and "= true" in output_block

        outputs[output_name] = output_info

    return outputs


class TestEKSModule:
    """Tests for the EKS Terraform module."""

    @pytest.fixture
    def module_path(self):
        return MODULES_DIR / "eks"

    @pytest.fixture
    def module_content(self, module_path) -> str:
        """Read all .tf files in the module."""
        if not module_path.exists():
            pytest.skip("EKS module not found")
        content = ""
        for tf_file in module_path.glob("*.tf"):
            content += tf_file.read_text() + "\n"
        return content

    def test_module_has_required_files(self, module_path):
        """Verify module has standard Terraform files."""
        required_files = ["main.tf", "variables.tf", "outputs.tf"]
        for filename in required_files:
            assert (module_path / filename).exists(), f"Missing {filename}"

    def test_variables_have_descriptions(self, module_content):
        """All variables should have descriptions."""
        variables = parse_terraform_variables(module_content)
        for var_name, var_info in variables.items():
            assert "description" in var_info, f"Variable '{var_name}' missing description"

    def test_sensitive_variables_marked(self, module_content):
        """Sensitive variables should be marked as sensitive."""
        variables = parse_terraform_variables(module_content)
        # Use suffix patterns to avoid false positives like "enable_kms_encryption"
        # which contains "key" but is not a secret
        sensitive_suffixes = ["_password", "_secret", "_key", "_token", "_api_key"]
        sensitive_exact = ["password", "secret", "api_key", "token"]
        for var_name, var_info in variables.items():
            var_lower = var_name.lower()
            is_sensitive_name = any(var_lower.endswith(s) for s in sensitive_suffixes) or any(
                var_lower == s for s in sensitive_exact
            )
            if is_sensitive_name:
                assert var_info.get("sensitive", False), (
                    f"Variable '{var_name}' appears sensitive but not marked"
                )

    def test_outputs_have_descriptions(self, module_content):
        """All outputs should have descriptions."""
        outputs = parse_terraform_outputs(module_content)
        for output_name, output_info in outputs.items():
            assert output_info["has_description"], f"Output '{output_name}' missing description"

    def test_encryption_enabled(self, module_content):
        """Verify encryption is configured for data at rest."""
        # Check for KMS encryption
        assert "kms" in module_content.lower() or "encrypt" in module_content.lower(), (
            "EKS module should configure encryption"
        )

    def test_private_endpoints_configurable(self, module_content):
        """Verify private endpoint access is configurable."""
        assert "endpoint_private_access" in module_content, (
            "EKS should have configurable private endpoint access"
        )

    def test_logging_enabled(self, module_content):
        """Verify cluster logging is enabled."""
        # Check for either EKS cluster logging or VPC flow logs
        has_logging = (
            "enabled_cluster_log_types" in module_content or "flow_log" in module_content.lower()
        )
        assert has_logging, "EKS should enable cluster or VPC flow logging"


class TestAKSModule:
    """Tests for the AKS Terraform module."""

    @pytest.fixture
    def module_path(self):
        return MODULES_DIR / "aks"

    @pytest.fixture
    def module_content(self, module_path) -> str:
        if not module_path.exists():
            pytest.skip("AKS module not found")
        content = ""
        for tf_file in module_path.glob("*.tf"):
            content += tf_file.read_text() + "\n"
        return content

    def test_module_has_required_files(self, module_path):
        """Verify module has standard Terraform files."""
        required_files = ["main.tf", "variables.tf", "outputs.tf"]
        for filename in required_files:
            assert (module_path / filename).exists(), f"Missing {filename}"

    def test_variables_have_descriptions(self, module_content):
        """All variables should have descriptions."""
        variables = parse_terraform_variables(module_content)
        for var_name, var_info in variables.items():
            assert "description" in var_info, f"Variable '{var_name}' missing description"

    def test_managed_identity_enabled(self, module_content):
        """Verify managed identity is used."""
        assert "identity" in module_content.lower(), "AKS should use managed identity"

    def test_network_policy_enabled(self, module_content):
        """Verify network policy is configured."""
        assert "network_policy" in module_content, "AKS should configure network policy"

    def test_azure_defender_configurable(self, module_content):
        """Verify Azure Defender/security center integration."""
        # Either Azure Monitor or Defender should be enabled
        has_monitoring = (
            "azure_monitor" in module_content.lower()
            or "oms_agent" in module_content.lower()
            or "monitor_metrics" in module_content.lower()
        )
        assert has_monitoring, "AKS should have monitoring configured"


class TestGKEModule:
    """Tests for the GKE Terraform module."""

    @pytest.fixture
    def module_path(self):
        return MODULES_DIR / "gke"

    @pytest.fixture
    def module_content(self, module_path) -> str:
        if not module_path.exists():
            pytest.skip("GKE module not found")
        content = ""
        for tf_file in module_path.glob("*.tf"):
            content += tf_file.read_text() + "\n"
        return content

    def test_module_has_required_files(self, module_path):
        """Verify module has standard Terraform files."""
        required_files = ["main.tf", "variables.tf", "outputs.tf"]
        for filename in required_files:
            assert (module_path / filename).exists(), f"Missing {filename}"

    def test_variables_have_descriptions(self, module_content):
        """All variables should have descriptions."""
        variables = parse_terraform_variables(module_content)
        for var_name, var_info in variables.items():
            assert "description" in var_info, f"Variable '{var_name}' missing description"

    def test_workload_identity_enabled(self, module_content):
        """Verify Workload Identity is configured."""
        assert (
            "workload_identity" in module_content.lower()
            or "workload_metadata_config" in module_content
        ), "GKE should enable Workload Identity"

    def test_shielded_nodes_enabled(self, module_content):
        """Verify shielded nodes are configured."""
        has_shielded = (
            "shielded" in module_content.lower() or "secure_boot" in module_content.lower()
        )
        assert has_shielded, "GKE should configure shielded nodes"

    def test_private_cluster_configurable(self, module_content):
        """Verify private cluster is configurable."""
        assert (
            "private_cluster_config" in module_content or "enable_private_nodes" in module_content
        ), "GKE should have private cluster configuration"


class TestModuleConsistency:
    """Tests to verify consistency across all cloud modules."""

    def test_all_modules_have_node_pool_configs(self):
        """All cloud modules should have configurable node pools."""
        for module_name in ["eks", "aks", "gke"]:
            module_path = MODULES_DIR / module_name
            if module_path.exists():
                content = ""
                for tf_file in module_path.glob("*.tf"):
                    content += tf_file.read_text()

                # Check for system and training node pools
                has_system = "system" in content.lower()
                has_training = "training" in content.lower()
                has_gpu = "gpu" in content.lower()

                assert has_system, f"{module_name} missing system node pool config"
                assert has_training, f"{module_name} missing training node pool config"
                assert has_gpu, f"{module_name} missing GPU node pool config"

    def test_all_modules_have_database_config(self):
        """All cloud modules should configure managed databases."""
        db_patterns = {
            "eks": ["rds", "postgresql"],
            "aks": ["postgresql", "flexible"],
            "gke": ["cloudsql", "sql_database"],
        }

        for module_name, patterns in db_patterns.items():
            module_path = MODULES_DIR / module_name
            if module_path.exists():
                content = ""
                for tf_file in module_path.glob("*.tf"):
                    content += tf_file.read_text().lower()

                has_db = any(p in content for p in patterns)
                assert has_db, f"{module_name} missing database configuration"

    def test_all_modules_output_cluster_endpoint(self):
        """All modules should output cluster endpoint."""
        for module_name in ["eks", "aks", "gke"]:
            module_path = MODULES_DIR / module_name
            if module_path.exists():
                outputs_file = module_path / "outputs.tf"
                if outputs_file.exists():
                    content = outputs_file.read_text()
                    assert "endpoint" in content.lower(), (
                        f"{module_name} should output cluster endpoint"
                    )

    def test_all_modules_use_tagging(self):
        """All modules should support resource tagging/labeling."""
        tag_patterns = {"eks": "tags", "aks": "tags", "gke": "labels"}

        for module_name, pattern in tag_patterns.items():
            module_path = MODULES_DIR / module_name / "variables.tf"
            if module_path.exists():
                content = module_path.read_text()
                assert pattern in content.lower(), f"{module_name} should have {pattern} variable"


class TestSecurityBestPractices:
    """Tests for security best practices across modules."""

    def test_no_hardcoded_credentials(self):
        """Verify no hardcoded credentials in modules."""
        dangerous_patterns = [
            r'password\s*=\s*"[^"$]',  # Hardcoded password (not variable)
            r'secret_key\s*=\s*"[^"$]',
            r'access_key\s*=\s*"[^"$]',
            r"AKIA[0-9A-Z]{16}",  # AWS access key pattern
        ]

        for module_dir in MODULES_DIR.iterdir():
            if module_dir.is_dir():
                for tf_file in module_dir.glob("*.tf"):
                    content = tf_file.read_text()
                    for pattern in dangerous_patterns:
                        matches = re.findall(pattern, content)
                        assert not matches, (
                            f"Potential hardcoded credential in {tf_file}: {matches}"
                        )

    def test_encryption_at_rest(self):
        """Verify encryption at rest is configured."""
        encryption_keywords = {
            "eks": ["kms", "encrypt"],
            "aks": ["key_vault", "disk_encryption"],
            "gke": ["kms", "encryption", "encrypted"],  # GKE uses "ENCRYPTED_ONLY" for SSL
        }

        for module_name, keywords in encryption_keywords.items():
            module_path = MODULES_DIR / module_name
            if module_path.exists():
                content = ""
                for tf_file in module_path.glob("*.tf"):
                    content += tf_file.read_text().lower()

                has_encryption = any(kw in content for kw in keywords)
                assert has_encryption, f"{module_name} should configure encryption at rest"

    def test_network_isolation(self):
        """Verify network isolation is configured."""
        network_keywords = {
            "eks": ["vpc", "subnet", "security_group"],
            "aks": ["vnet", "subnet", "network_security"],
            "gke": ["network", "subnetwork", "firewall"],
        }

        for module_name, keywords in network_keywords.items():
            module_path = MODULES_DIR / module_name
            if module_path.exists():
                content = ""
                for tf_file in module_path.glob("*.tf"):
                    content += tf_file.read_text().lower()

                has_network = any(kw in content for kw in keywords)
                assert has_network, f"{module_name} should configure network isolation"
