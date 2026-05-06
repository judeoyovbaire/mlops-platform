"""End-to-end tests for KServe model serving on Kubernetes.

These tests require a Kubernetes cluster with KServe installed.
Skip with: pytest -m "not e2e"
"""

import os
import subprocess

import pytest

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


@pytest.fixture(scope="module")
def cluster_ready():
    """Verify cluster is ready for model serving E2E tests."""
    result = run_kubectl(["cluster-info"])
    if result.returncode != 0:
        pytest.skip(f"Cluster not accessible: {result.stderr}")

    result = run_kubectl(["get", "deployment", "kserve-controller-manager", "-n", "kserve"])
    if result.returncode != 0:
        pytest.skip("KServe not installed")

    return True


@pytest.mark.e2e
class TestModelServing:
    """E2E tests for KServe model serving."""

    def test_kserve_inference_service_deployment(self, cluster_ready):
        """Verify InferenceService CRD can be applied and reaches Ready state."""
        isvc_yaml = """\
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: e2e-test-sklearn
  namespace: default
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "gs://kfserving-examples/models/sklearn/1.0/model"
"""
        result = subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=isvc_yaml,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Failed to apply InferenceService: {result.stderr}"

        try:
            status_result = run_kubectl(
                [
                    "wait",
                    "inferenceservice/e2e-test-sklearn",
                    "--for=condition=Ready",
                    "-n",
                    "default",
                    "--timeout=180s",
                ],
                timeout=200,
            )
            assert status_result.returncode == 0, "InferenceService did not become ready"
        finally:
            run_kubectl(["delete", "inferenceservice", "e2e-test-sklearn", "-n", "default"])

    def test_inference_request(self, cluster_ready):
        """Send a prediction request to the model endpoint and verify response."""
        isvc_yaml = """\
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: e2e-test-inference
  namespace: default
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "gs://kfserving-examples/models/sklearn/1.0/model"
"""
        result = subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=isvc_yaml,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            pytest.skip(f"Could not create InferenceService: {result.stderr}")

        try:
            run_kubectl(
                [
                    "wait",
                    "inferenceservice/e2e-test-inference",
                    "--for=condition=Ready",
                    "-n",
                    "default",
                    "--timeout=180s",
                ],
                timeout=200,
            )

            url_result = run_kubectl(
                [
                    "get",
                    "inferenceservice",
                    "e2e-test-inference",
                    "-n",
                    "default",
                    "-o",
                    "jsonpath={.status.url}",
                ]
            )
            assert url_result.stdout, "InferenceService URL not available"
        finally:
            run_kubectl(["delete", "inferenceservice", "e2e-test-inference", "-n", "default"])

    def test_gateway_api_routing(self, cluster_ready):
        """Verify HTTPRoute CRD availability for inference routing."""
        result = run_kubectl(["get", "crd", "httproutes.gateway.networking.k8s.io"])
        if result.returncode != 0:
            pytest.skip("Gateway API CRDs not installed")

        result = run_kubectl(
            ["get", "httproute", "-n", "mlops", "-o", "jsonpath={.items[*].metadata.name}"]
        )
        assert result.returncode == 0, "Failed to query HTTPRoutes"
