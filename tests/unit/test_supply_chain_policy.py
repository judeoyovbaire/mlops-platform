"""Keeps the image-signature trust root pinned to this repository.

The Kyverno verifyImages rule cannot run hermetically (it calls Rekor and the
registry), so tests/policies/ cannot exercise it. Before JDH-404 it accepted
`ghcr.io/*/mlops-platform/*` signed by `https://github.com/.*/...`, i.e. any
GitHub account with a repo of the same name. These assertions stop that
regression and keep the cluster policy and the CI verify step in lockstep.
"""

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
REPO = "judeoyovbaire/mlops-platform"
SUBJECT = f"https://github.com/{REPO}/.github/workflows/build-sign-publish.yaml@refs/heads/main"
ISSUER = "https://token.actions.githubusercontent.com"


def _verify_rule() -> dict:
    docs = yaml.safe_load_all(
        (ROOT / "infrastructure/kubernetes/governance/image-signature-policy.yaml").read_text()
    )
    policy = next(d for d in docs if d and d["metadata"]["name"] == "verify-image-signatures")
    assert policy["spec"]["validationFailureAction"] == "Enforce"
    (rule,) = policy["spec"]["rules"]
    (verify,) = rule["verifyImages"]
    return verify


def test_image_references_scoped_to_this_repo() -> None:
    assert _verify_rule()["imageReferences"] == [f"ghcr.io/{REPO}/*"]


def test_keyless_identity_is_exact() -> None:
    (attestor,) = _verify_rule()["attestors"]
    (entry,) = attestor["entries"]
    keyless = entry["keyless"]
    assert keyless["issuer"] == ISSUER
    assert keyless["subject"] == SUBJECT
    assert "subjectRegExp" not in keyless


def test_ci_verifies_the_same_identity_by_digest() -> None:
    workflow = (ROOT / ".github/workflows/build-sign-publish.yaml").read_text()
    assert (
        '--certificate-identity="https://github.com/${{ github.repository }}'
        '/.github/workflows/build-sign-publish.yaml@refs/heads/main"'
    ) in workflow
    assert "--certificate-identity-regexp" not in workflow
    assert ":latest" not in workflow.split("cosign verify", 1)[1].split("\n\n", 1)[0]
