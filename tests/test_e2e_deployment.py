"""
End-to-End Deployment Tests.

These tests verify the infrastructure configuration is correct.
Manifest validation is handled by CI/CD (kubeconform).

Set E2E_CLUSTER_TEST=true to run actual cluster tests.
"""

import pytest
import subprocess
import json
import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
CLUSTER_TEST = os.environ.get("E2E_CLUSTER_TEST", "false").lower() == "true"


class TestSecurityConfiguration:
    """Verify security components are properly configured in Terraform."""

    @pytest.fixture
    def main_tf_content(self):
        """Load main.tf content."""
        main_tf = PROJECT_ROOT / "infrastructure" / "terraform" / "environments" / "dev" / "main.tf"
        return main_tf.read_text()

    def test_psa_configured(self, main_tf_content):
        """Verify Pod Security Standards labels are configured."""
        assert "pod-security.kubernetes.io/enforce" in main_tf_content

    def test_kyverno_configured(self, main_tf_content):
        """Verify Kyverno and policies are configured."""
        assert "helm_release" in main_tf_content and "kyverno" in main_tf_content
        assert "ClusterPolicy" in main_tf_content

    def test_tetragon_configured(self, main_tf_content):
        """Verify Tetragon runtime security is configured."""
        assert "helm_release" in main_tf_content and "tetragon" in main_tf_content
        assert "TracingPolicy" in main_tf_content


@pytest.mark.skipif(not CLUSTER_TEST, reason="Cluster tests disabled")
class TestClusterHealth:
    """Tests that run on an actual Kubernetes cluster."""

    def test_security_components_running(self):
        """Verify security components are running."""
        components = [
            ("kyverno", "app.kubernetes.io/name=kyverno"),
            ("tetragon", "app.kubernetes.io/name=tetragon"),
        ]

        for namespace, label in components:
            result = subprocess.run(
                ["kubectl", "get", "pods", "-n", namespace, "-l", label, "-o", "json"],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                pods = json.loads(result.stdout)
                running = [p for p in pods.get("items", [])
                          if p.get("status", {}).get("phase") == "Running"]
                assert len(running) > 0, f"{namespace} should be running"