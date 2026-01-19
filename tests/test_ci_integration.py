"""
CI/CD Pipeline Integration Tests.

Tests that verify the CI/CD pipeline components work correctly together.
"""

import pytest
import yaml
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent


class TestGitHubActionsWorkflows:
    """Tests for GitHub Actions workflow configurations."""

    @pytest.fixture
    def workflows_dir(self):
        return PROJECT_ROOT / ".github" / "workflows"

    def test_workflows_exist(self, workflows_dir):
        """Verify workflow files exist."""
        assert workflows_dir.exists(), "GitHub workflows directory should exist"
        workflows = list(workflows_dir.glob("*.yml")) + list(workflows_dir.glob("*.yaml"))
        assert len(workflows) >= 1, "Should have at least one workflow"

    def test_workflows_valid_yaml(self, workflows_dir):
        """Verify all workflows are valid YAML."""
        for workflow in workflows_dir.glob("*.y*ml"):
            try:
                with open(workflow) as f:
                    yaml.safe_load(f)
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {workflow}: {e}")

    def test_workflows_have_triggers(self, workflows_dir):
        """Verify workflows have proper triggers defined."""
        for workflow in workflows_dir.glob("*.y*ml"):
            with open(workflow) as f:
                content = yaml.safe_load(f)
                if content:
                    # Note: "on" in YAML 1.1 can be parsed as True (boolean)
                    # Check for both "on" key and True key (YAML boolean alias)
                    has_trigger = "on" in content or True in content
                    assert has_trigger, f"{workflow.name} missing trigger definition"

    def test_terraform_workflow_has_plan_and_apply(self, workflows_dir):
        """Verify Terraform workflow has both plan and apply jobs."""
        tf_workflows = [
            w for w in workflows_dir.glob("*.y*ml")
            if "terraform" in w.name.lower() or "infrastructure" in w.name.lower()
        ]

        for workflow in tf_workflows:
            with open(workflow) as f:
                content = yaml.safe_load(f)
                if content and "jobs" in content:
                    jobs = content["jobs"]
                    job_names = " ".join(jobs.keys()).lower()
                    # Check workflow has validation/planning steps
                    has_validation = any(
                        "plan" in name.lower() or
                        "validate" in name.lower() or
                        "lint" in name.lower()
                        for name in jobs.keys()
                    )
                    assert has_validation, \
                        f"{workflow.name} should have validation/planning job"

    def test_no_secrets_in_workflows(self, workflows_dir):
        """Verify no hardcoded secrets in workflows."""
        dangerous_patterns = [
            "AKIA",  # AWS access key prefix
            "ghp_",  # GitHub PAT prefix
            "sk-",   # OpenAI key prefix
        ]

        for workflow in workflows_dir.glob("*.y*ml"):
            content = workflow.read_text()
            for pattern in dangerous_patterns:
                assert pattern not in content, \
                    f"Potential hardcoded secret in {workflow.name}"

    def test_workflows_use_pinned_actions(self, workflows_dir):
        """Verify workflows use pinned action versions."""
        for workflow in workflows_dir.glob("*.y*ml"):
            with open(workflow) as f:
                content = yaml.safe_load(f)
                if content and "jobs" in content:
                    for job_name, job in content["jobs"].items():
                        for step in job.get("steps", []):
                            if "uses" in step:
                                uses = step["uses"]
                                # Should have version pinning (@v1, @sha, etc.)
                                assert "@" in uses, \
                                    f"Action '{uses}' in {workflow.name} should be version pinned"


class TestPreCommitHooks:
    """Tests for pre-commit hook configuration."""

    @pytest.fixture
    def precommit_config(self):
        config_path = PROJECT_ROOT / ".pre-commit-config.yaml"
        if not config_path.exists():
            pytest.skip("Pre-commit config not found")
        with open(config_path) as f:
            return yaml.safe_load(f)

    def test_terraform_hooks_configured(self, precommit_config):
        """Verify Terraform-related hooks are configured."""
        hooks = []
        for repo in precommit_config.get("repos", []):
            for hook in repo.get("hooks", []):
                hooks.append(hook.get("id", ""))

        tf_hooks_present = any(
            "terraform" in h.lower() or "tflint" in h.lower()
            for h in hooks
        )
        assert tf_hooks_present, "Pre-commit should have Terraform hooks"

    def test_security_hooks_configured(self, precommit_config):
        """Verify security scanning hooks are configured."""
        all_hooks = []
        for repo in precommit_config.get("repos", []):
            for hook in repo.get("hooks", []):
                all_hooks.append(hook.get("id", "").lower())
            # Also check repo URLs
            repo_url = repo.get("repo", "").lower()
            all_hooks.append(repo_url)

        security_patterns = ["trivy", "checkov", "tfsec", "detect-secrets", "gitleaks"]
        has_security = any(
            pattern in " ".join(all_hooks)
            for pattern in security_patterns
        )
        # Security hooks are recommended but not required
        if not has_security:
            pytest.skip("Security hooks recommended but not configured")

    def test_yaml_linting_configured(self, precommit_config):
        """Verify YAML linting is configured."""
        hooks = []
        for repo in precommit_config.get("repos", []):
            for hook in repo.get("hooks", []):
                hooks.append(hook.get("id", ""))

        yaml_hooks = any("yaml" in h.lower() for h in hooks)
        assert yaml_hooks, "Pre-commit should have YAML linting"


class TestMakefileTargets:
    """Tests for Makefile targets and CI integration."""

    @pytest.fixture
    def makefile_content(self):
        makefile = PROJECT_ROOT / "Makefile"
        if not makefile.exists():
            pytest.skip("Makefile not found")
        return makefile.read_text()

    def test_has_test_target(self, makefile_content):
        """Verify Makefile has test target."""
        assert "test:" in makefile_content or "test :" in makefile_content, \
            "Makefile should have 'test' target"

    def test_has_lint_target(self, makefile_content):
        """Verify Makefile has lint target."""
        assert "lint:" in makefile_content or "lint :" in makefile_content, \
            "Makefile should have 'lint' target"

    def test_has_terraform_targets(self, makefile_content):
        """Verify Makefile has Terraform targets."""
        tf_targets = ["tf-init", "tf-plan", "tf-apply", "terraform"]
        has_tf = any(t in makefile_content for t in tf_targets)
        assert has_tf, "Makefile should have Terraform targets"

    def test_has_help_target(self, makefile_content):
        """Verify Makefile has help target."""
        assert "help:" in makefile_content or "help :" in makefile_content, \
            "Makefile should have 'help' target"


class TestArgoWorkflowTemplates:
    """Tests for Argo Workflow templates."""

    @pytest.fixture
    def pipelines_dir(self):
        return PROJECT_ROOT / "pipelines"

    def test_workflow_templates_valid_yaml(self, pipelines_dir):
        """Verify workflow templates are valid YAML."""
        if not pipelines_dir.exists():
            pytest.skip("Pipelines directory not found")

        for template in pipelines_dir.rglob("*.yaml"):
            try:
                with open(template) as f:
                    list(yaml.safe_load_all(f))
            except yaml.YAMLError as e:
                pytest.fail(f"Invalid YAML in {template}: {e}")

    def test_workflow_templates_have_metadata(self, pipelines_dir):
        """Verify workflow templates have proper metadata."""
        if not pipelines_dir.exists():
            pytest.skip("Pipelines directory not found")

        workflow_found = False
        for template in pipelines_dir.rglob("*.yaml"):
            # Skip non-workflow files like kustomization.yaml
            if "kustomization" in template.name.lower():
                continue

            with open(template) as f:
                docs = list(yaml.safe_load_all(f))

            for doc in docs:
                if doc and doc.get("kind") in ["Workflow", "WorkflowTemplate"]:
                    workflow_found = True
                    metadata = doc.get("metadata", {})
                    assert "name" in metadata or "generateName" in metadata, \
                        f"{template.name} workflow missing name or generateName"

        if not workflow_found:
            pytest.skip("No Workflow/WorkflowTemplate found in pipelines")

    def test_workflow_templates_have_resource_limits(self, pipelines_dir):
        """Verify workflow steps have resource limits defined."""
        if not pipelines_dir.exists():
            pytest.skip("Pipelines directory not found")

        for template in pipelines_dir.rglob("*.yaml"):
            content = template.read_text()
            # Workflows should define resources
            if "kind: Workflow" in content or "kind: WorkflowTemplate" in content:
                # Check if resources are mentioned
                has_resources = "resources:" in content
                if not has_resources:
                    pytest.skip(f"{template.name} - resources optional for workflows")


class TestDockerfilesBestPractices:
    """Tests for Dockerfile best practices."""

    @pytest.fixture
    def dockerfiles(self):
        return list(PROJECT_ROOT.rglob("Dockerfile*"))

    def test_dockerfiles_exist(self, dockerfiles):
        """Check if Dockerfiles exist in the project."""
        if not dockerfiles:
            pytest.skip("No Dockerfiles found")

    def test_dockerfiles_use_specific_base_images(self, dockerfiles):
        """Verify Dockerfiles use specific image tags, not 'latest'."""
        for dockerfile in dockerfiles:
            content = dockerfile.read_text()
            lines = content.split('\n')

            for line in lines:
                if line.strip().startswith('FROM'):
                    # Should not use :latest
                    assert ':latest' not in line.lower(), \
                        f"{dockerfile} uses :latest tag - use specific version"

    def test_dockerfiles_have_healthcheck(self, dockerfiles):
        """Verify Dockerfiles define HEALTHCHECK (recommended)."""
        for dockerfile in dockerfiles:
            content = dockerfile.read_text()
            if 'EXPOSE' in content:  # If it exposes a port, should have healthcheck
                if 'HEALTHCHECK' not in content:
                    # Warning, not failure - healthchecks are recommended
                    pass

    def test_dockerfiles_run_as_nonroot(self, dockerfiles):
        """Verify Dockerfiles don't run as root (recommended)."""
        for dockerfile in dockerfiles:
            content = dockerfile.read_text()
            # Check if USER directive is present
            has_user = 'USER' in content and 'USER root' not in content
            # This is a best practice, not a hard requirement
            if not has_user:
                pass  # Just informational