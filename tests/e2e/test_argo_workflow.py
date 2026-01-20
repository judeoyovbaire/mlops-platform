"""End-to-end tests for Argo Workflows on Kubernetes.

These tests require a Kubernetes cluster with Argo Workflows installed.
Skip with: pytest -m "not e2e"
"""

import os
import subprocess
import time

import pytest

# Skip all tests in this module if E2E_CLUSTER_TEST is not set
pytestmark = pytest.mark.skipif(
    os.environ.get("E2E_CLUSTER_TEST") != "true",
    reason="E2E tests require E2E_CLUSTER_TEST=true and a running cluster",
)


def run_kubectl(args: list[str], timeout: int = 30) -> subprocess.CompletedProcess:
    """Run kubectl command and return result."""
    return subprocess.run(
        ["kubectl"] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_argo(args: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    """Run argo CLI command and return result."""
    return subprocess.run(
        ["argo"] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


@pytest.fixture(scope="module")
def cluster_ready():
    """Verify cluster is ready for E2E tests."""
    # Check kubectl connectivity
    result = run_kubectl(["cluster-info"])
    if result.returncode != 0:
        pytest.skip(f"Cluster not accessible: {result.stderr}")

    # Check Argo Workflows is installed
    result = run_kubectl(["get", "deployment", "argo-workflows-server", "-n", "argo"])
    if result.returncode != 0:
        pytest.skip("Argo Workflows not installed")

    # Wait for Argo Workflows to be ready
    result = run_kubectl(
        [
            "wait",
            "--for=condition=available",
            "deployment/argo-workflows-server",
            "-n",
            "argo",
            "--timeout=120s",
        ]
    )
    if result.returncode != 0:
        pytest.skip("Argo Workflows not ready")

    return True


@pytest.mark.e2e
class TestArgoWorkflow:
    """E2E tests for Argo Workflows."""

    def test_workflow_template_exists(self, cluster_ready):
        """Test that ML training workflow template is deployed."""
        result = run_kubectl(
            ["get", "workflowtemplate", "ml-training-pipeline", "-n", "argo"]
        )

        # Template might not be deployed yet - that's OK for this test
        if result.returncode != 0:
            pytest.skip("WorkflowTemplate not deployed - deploy with kubectl apply -k pipelines/training")

        assert "ml-training-pipeline" in result.stdout

    def test_submit_simple_workflow(self, cluster_ready):
        """Test submitting a simple test workflow."""
        # Create a simple workflow for testing
        workflow_yaml = """
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: e2e-test-
  namespace: argo
spec:
  entrypoint: hello
  templates:
    - name: hello
      container:
        image: busybox
        command: [echo]
        args: ["E2E test successful"]
"""
        # Submit workflow
        result = subprocess.run(
            ["kubectl", "create", "-f", "-"],
            input=workflow_yaml,
            capture_output=True,
            text=True,
            timeout=30,
        )

        assert result.returncode == 0, f"Failed to submit workflow: {result.stderr}"

        # Extract workflow name
        workflow_name = result.stdout.strip().split("/")[-1].replace(" created", "")

        # Wait for workflow to complete
        result = run_kubectl(
            [
                "wait",
                f"workflow/{workflow_name}",
                "--for=condition=Completed",
                "-n",
                "argo",
                "--timeout=60s",
            ]
        )

        # Check workflow succeeded
        result = run_kubectl(
            ["get", "workflow", workflow_name, "-n", "argo", "-o", "jsonpath={.status.phase}"]
        )

        assert result.stdout == "Succeeded", f"Workflow failed: {result.stderr}"

        # Cleanup
        run_kubectl(["delete", "workflow", workflow_name, "-n", "argo"])

    def test_argo_server_accessible(self, cluster_ready):
        """Test that Argo Workflows server is accessible."""
        result = run_argo(["list", "-n", "argo"])

        # Should succeed even if no workflows exist
        assert result.returncode == 0, f"Argo server not accessible: {result.stderr}"