"""Drift check for the serving runtime contract.

pipelines/serving-runtime-contract.yaml is the single source of truth for
the versions that must agree across the train->serve pickle boundary. These
tests fail CI when any surface (champion template, serving-load-test gate
image, training Dockerfile, training requirements pins) drifts from it.

Each assertion message names the file to fix - the bump procedure is in the
contract file's header.
"""

import re
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]

CONTRACT_PATH = REPO_ROOT / "pipelines" / "serving-runtime-contract.yaml"
CHAMPION_TEMPLATE = REPO_ROOT / "examples" / "kserve" / "champion-inferenceservice.template.yaml"
TRAINING_WORKFLOW = REPO_ROOT / "pipelines" / "training" / "ml-training-workflow.yaml"
TRAINING_DOCKERFILE = REPO_ROOT / "pipelines" / "training" / "Dockerfile"
TRAINING_REQUIREMENTS = REPO_ROOT / "pipelines" / "training" / "requirements.in"
PRETRAINED_WORKFLOW = REPO_ROOT / "pipelines" / "pretrained" / "hf-pretrained-workflow.yaml"
HELM_VERSIONS = REPO_ROOT / "infrastructure" / "terraform" / "helm-versions.auto.tfvars"


@pytest.fixture(scope="module")
def contract():
    with open(CONTRACT_PATH) as f:
        return yaml.safe_load(f)


class TestServingRuntimeContract:
    def test_contract_is_internally_consistent(self, contract):
        """The image tag must carry the declared mlserver version."""
        assert contract["mlserver_version"] in contract["mlserver_image"], (
            f"mlserver_image '{contract['mlserver_image']}' does not contain "
            f"mlserver_version '{contract['mlserver_version']}' - fix {CONTRACT_PATH}"
        )

    def test_champion_template_runtime_version(self, contract):
        """KServe serves with the runtime the contract declares."""
        template = CHAMPION_TEMPLATE.read_text()
        m = re.search(r'runtimeVersion:\s*"([^"]+)"', template)
        assert m, f"runtimeVersion not found in {CHAMPION_TEMPLATE}"
        assert m.group(1) == contract["mlserver_version"], (
            f"{CHAMPION_TEMPLATE} pins runtimeVersion {m.group(1)}, contract says "
            f"{contract['mlserver_version']}"
        )

    def test_serving_load_test_gate_image(self, contract):
        """The pre-registration load test must run in the contract image -
        testing in any other image proves nothing about serving."""
        docs = list(yaml.safe_load_all(TRAINING_WORKFLOW.read_text()))
        template_doc = next(d for d in docs if d.get("kind") == "WorkflowTemplate")
        gate = next(
            t for t in template_doc["spec"]["templates"] if t["name"] == "serving-load-test"
        )
        image = gate["script"]["image"]
        assert image == contract["mlserver_image"], (
            f"serving-load-test in {TRAINING_WORKFLOW} runs {image}, contract says "
            f"{contract['mlserver_image']}"
        )

    def test_training_dockerfile_python(self, contract):
        """Pickles must be produced by the interpreter that unpickles them."""
        dockerfile = TRAINING_DOCKERFILE.read_text()
        m = re.search(r"^FROM python:(\d+\.\d+)-slim", dockerfile, flags=re.MULTILINE)
        assert m, f"python base image not found in {TRAINING_DOCKERFILE}"
        assert m.group(1) == contract["python_version"], (
            f"{TRAINING_DOCKERFILE} builds on python {m.group(1)}, contract says "
            f"{contract['python_version']}"
        )

    def test_training_requirements_pins(self, contract):
        """Pickle-critical libraries must be pinned to the runtime's versions."""
        requirements = TRAINING_REQUIREMENTS.read_text()
        for lib, version in contract["pinned_libraries"].items():
            m = re.search(rf"^{re.escape(lib)}==(\S+)", requirements, flags=re.MULTILINE)
            assert m, f"{lib} is not pinned in {TRAINING_REQUIREMENTS}"
            assert m.group(1) == version, (
                f"{TRAINING_REQUIREMENTS} pins {lib}=={m.group(1)}, contract says {version}"
            )


class TestHuggingFaceRuntimeContract:
    """The HF pretrained pipeline's gate must run the image KServe serves
    huggingface-format models with - and that image's tag rides on the
    kserve chart version, so all three must agree."""

    def test_pretrained_gate_image_matches_contract(self, contract):
        docs = list(yaml.safe_load_all(PRETRAINED_WORKFLOW.read_text()))
        template_doc = next(d for d in docs if d.get("kind") == "WorkflowTemplate")
        gate = next(
            t for t in template_doc["spec"]["templates"] if t["name"] == "serving-load-test"
        )
        image = gate["script"]["image"]
        assert image == contract["huggingface_runtime_image"], (
            f"{PRETRAINED_WORKFLOW} gate runs {image}, contract says "
            f"{contract['huggingface_runtime_image']}"
        )

    def test_huggingface_tag_matches_kserve_chart_version(self, contract):
        """kserve/huggingfaceserver:<tag> is versioned WITH the kserve chart -
        bumping helm_kserve_version without the contract (or vice versa)
        would gate against a different runtime than the cluster serves."""
        m = re.search(r'helm_kserve_version\s*=\s*"([^"]+)"', HELM_VERSIONS.read_text())
        assert m, f"helm_kserve_version not found in {HELM_VERSIONS}"
        tag = contract["huggingface_runtime_image"].rsplit(":", 1)[1]
        assert tag == m.group(1), (
            f"contract huggingface tag {tag} != helm_kserve_version {m.group(1)}"
        )
