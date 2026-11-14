"""End-to-end tests for Argo Workflows on Kubernetes.

Run by the CI e2e-test job against a Kind cluster with Argo's
quick-start-minimal manifest and the pipeline WorkflowTemplate applied
(kubectl apply -k pipelines/training). With E2E_CLUSTER_TEST=true a missing
prerequisite fails the run instead of skipping it, so an all-skip run can
no longer pass.

Deployment names default to the quick-start ones (argo-server,
workflow-controller). On the Helm install (EKS) set
ARGO_SERVER_DEPLOYMENT=argo-workflows-server and
ARGO_CONTROLLER_DEPLOYMENT=argo-workflows-workflow-controller.

Skip with: pytest -m "not e2e"
"""

import os
import subprocess

import pytest

# Skip all tests in this module if E2E_CLUSTER_TEST is not set
pytestmark = pytest.mark.skipif(
    os.environ.get("E2E_CLUSTER_TEST") != "true",
    reason="E2E tests require E2E_CLUSTER_TEST=true and a running cluster",
)

ARGO_NAMESPACE = os.environ.get("ARGO_NAMESPACE", "argo")
ARGO_SERVER_DEPLOYMENT = os.environ.get("ARGO_SERVER_DEPLOYMENT", "argo-server")
ARGO_CONTROLLER_DEPLOYMENT = os.environ.get("ARGO_CONTROLLER_DEPLOYMENT", "workflow-controller")
PIPELINE_TEMPLATE = "ml-training-pipeline"


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
    """Fail (not skip) unless the cluster and Argo Workflows are usable."""
    result = run_kubectl(["cluster-info"])
    if result.returncode != 0:
        pytest.fail(f"Cluster not accessible: {result.stderr}")

    for deployment in (ARGO_SERVER_DEPLOYMENT, ARGO_CONTROLLER_DEPLOYMENT):
        result = run_kubectl(["get", "deployment", deployment, "-n", ARGO_NAMESPACE])
        if result.returncode != 0:
            pytest.fail(
                f"deployment/{deployment} not found in namespace {ARGO_NAMESPACE}: "
                f"{result.stderr.strip()}"
            )

        result = run_kubectl(
            [
                "wait",
                "--for=condition=available",
                f"deployment/{deployment}",
                "-n",
                ARGO_NAMESPACE,
                "--timeout=120s",
            ],
            timeout=150,
        )
        if result.returncode != 0:
            pytest.fail(f"deployment/{deployment} not available: {result.stderr.strip()}")

    return True


@pytest.mark.e2e
class TestArgoWorkflow:
    """E2E tests for Argo Workflows."""

    def test_workflow_template_exists(self, cluster_ready):
        """The training WorkflowTemplate is accepted by the v4 CRD and present."""
        result = run_kubectl(["get", "workflowtemplate", PIPELINE_TEMPLATE, "-n", ARGO_NAMESPACE])

        assert result.returncode == 0, (
            f"workflowtemplate/{PIPELINE_TEMPLATE} missing; "
            f"the job applies it with kubectl apply -k pipelines/training: {result.stderr}"
        )
        assert PIPELINE_TEMPLATE in result.stdout

    def test_submit_simple_workflow(self, cluster_ready):
        """A one-step workflow runs to Succeeded with the quick-start RBAC."""
        workflow_yaml = f"""
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: e2e-test-
  namespace: {ARGO_NAMESPACE}
spec:
  entrypoint: hello
  templates:
    - name: hello
      container:
        image: docker.io/library/busybox:1.37.0
        command: [echo]
        args: ["E2E test successful"]
"""
        result = subprocess.run(
            ["kubectl", "create", "-f", "-"],
            input=workflow_yaml,
            capture_output=True,
            text=True,
            timeout=30,
        )

        assert result.returncode == 0, f"Failed to submit workflow: {result.stderr}"

        # "workflow.argoproj.io/e2e-test-abcde created"
        workflow_name = result.stdout.strip().split("/")[-1].replace(" created", "")

        try:
            result = run_kubectl(
                [
                    "wait",
                    f"workflow/{workflow_name}",
                    "--for=condition=Completed",
                    "-n",
                    ARGO_NAMESPACE,
                    "--timeout=120s",
                ],
                timeout=150,
            )
            assert result.returncode == 0, f"Workflow did not complete: {result.stderr}"

            result = run_kubectl(
                [
                    "get",
                    "workflow",
                    workflow_name,
                    "-n",
                    ARGO_NAMESPACE,
                    "-o",
                    "jsonpath={.status.phase} {.status.message}",
                ]
            )
            phase, _, message = result.stdout.partition(" ")
            assert phase == "Succeeded", f"Workflow phase {phase!r}: {message}"
        finally:
            run_kubectl(["delete", "workflow", workflow_name, "-n", ARGO_NAMESPACE])

    def test_argo_cli_lists_workflows(self, cluster_ready):
        """The argo CLI can list workflows in the namespace."""
        result = run_argo(["list", "-n", ARGO_NAMESPACE])

        # Should succeed even if no workflows exist
        assert result.returncode == 0, f"Argo CLI failed: {result.stderr}"
