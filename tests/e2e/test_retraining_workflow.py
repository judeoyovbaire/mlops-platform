"""End-to-end tests for the automated retraining CronWorkflow.

These tests validate YAML structure and DAG dependencies without
requiring a running cluster.
"""

import os

import pytest
import yaml

pytestmark = pytest.mark.skipif(
    os.environ.get("E2E_CLUSTER_TEST") != "true",
    reason="E2E tests require E2E_CLUSTER_TEST=true and a running cluster",
)

WORKFLOW_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "pipelines",
    "retraining",
    "automated-retraining-workflow.yaml",
)


@pytest.fixture(scope="module")
def workflow_doc():
    """Load and parse the retraining workflow YAML."""
    with open(WORKFLOW_PATH) as f:
        docs = list(yaml.safe_load_all(f))
    assert len(docs) >= 1, "Expected at least one YAML document"
    return docs[0]


class TestRetrainingWorkflowStructure:
    """Validate the retraining workflow YAML structure."""

    def test_is_cron_workflow(self, workflow_doc):
        """Verify the document is an Argo CronWorkflow."""
        assert workflow_doc["apiVersion"] == "argoproj.io/v1alpha1"
        assert workflow_doc["kind"] == "CronWorkflow"

    def test_has_schedule(self, workflow_doc):
        """Verify cron schedule is configured."""
        assert "schedule" in workflow_doc["spec"]

    def test_dag_has_expected_tasks(self, workflow_doc):
        """Verify the DAG contains the expected pipeline steps."""
        templates = workflow_doc["spec"]["workflowSpec"]["templates"]
        dag_template = next(t for t in templates if t["name"] == "automated-retrain")
        task_names = [t["name"] for t in dag_template["dag"]["tasks"]]

        assert "check-drift" in task_names
        assert "retrain" in task_names
        assert "validate-new-model" in task_names
        assert "promote-model" in task_names

    def test_retrain_depends_on_drift(self, workflow_doc):
        """Verify retrain step depends on check-drift."""
        templates = workflow_doc["spec"]["workflowSpec"]["templates"]
        dag_template = next(t for t in templates if t["name"] == "automated-retrain")
        retrain_task = next(
            t for t in dag_template["dag"]["tasks"] if t["name"] == "retrain"
        )

        assert "check-drift" in retrain_task["dependencies"]
        assert "when" in retrain_task  # Should be conditional on drift

    def test_promote_depends_on_validate(self, workflow_doc):
        """Verify promote step depends on validate-new-model."""
        templates = workflow_doc["spec"]["workflowSpec"]["templates"]
        dag_template = next(t for t in templates if t["name"] == "automated-retrain")
        promote_task = next(
            t for t in dag_template["dag"]["tasks"] if t["name"] == "promote-model"
        )

        assert "validate-new-model" in promote_task["dependencies"]
        assert "when" in promote_task  # Should be conditional on validation

    def test_security_context_set(self, workflow_doc):
        """Verify security context is configured."""
        sec_ctx = workflow_doc["spec"]["workflowSpec"]["securityContext"]
        assert sec_ctx["runAsNonRoot"] is True
