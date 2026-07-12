#!/bin/bash
set -euo pipefail

# Kyverno policy tests - see tests/policies/*/kyverno-test.yaml.
#
# Two generated fixtures make these tests honest:
# 1. The champion InferenceService template is rendered with envsubst,
#    exactly as the deploy workflow renders it - policy/template contract
#    drift fails here instead of at deploy time.
# 2. audit-unsigned-images is extracted from image-signature-policy.yaml so
#    the CLI never executes its file-mate verify-image-signatures (live
#    cosign/Rekor verification - not hermetic).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POLICY_TESTS="${PROJECT_ROOT}/tests/policies"

command -v kyverno >/dev/null || {
    echo "kyverno CLI not found (brew install kyverno / kyverno/action-install-cli)" >&2
    exit 1
}

# Fixture 1: render the champion template with representative values.
mkdir -p "${POLICY_TESTS}/model-registry/rendered"
MODEL_NAME=iris-classifier \
MODEL_VERSION=1 \
MODEL_RUN_ID=test-run-id \
MODEL_EXPERIMENT_ID=1 \
MODEL_STORAGE_URI=s3://example-bucket/1/test-run-id/artifacts/serving_model \
envsubst '$MODEL_NAME $MODEL_STORAGE_URI $MODEL_VERSION $MODEL_RUN_ID $MODEL_EXPERIMENT_ID' \
    < "${PROJECT_ROOT}/examples/kserve/champion-inferenceservice.template.yaml" \
    > "${POLICY_TESTS}/model-registry/rendered/champion-rendered.yaml"

MODEL_NAME=sentiment-classifier \
MODEL_VERSION=1 \
MODEL_RUN_ID=test-run-id \
MODEL_EXPERIMENT_ID=2 \
MODEL_STORAGE_URI=s3://example-bucket/2/test-run-id/artifacts/hf_model \
HF_REVISION=714eb0fa89d2f80546fda750413ed43d93601a13 \
HF_TASK=text-classification \
envsubst '$MODEL_NAME $MODEL_STORAGE_URI $MODEL_VERSION $MODEL_RUN_ID $MODEL_EXPERIMENT_ID $HF_REVISION $HF_TASK' \
    < "${PROJECT_ROOT}/examples/kserve/hf-inferenceservice.template.yaml" \
    > "${POLICY_TESTS}/model-registry/rendered/hf-rendered.yaml"

# Fixture 2: extract the audit policy from the shared file.
mkdir -p "${POLICY_TESTS}/image-audit/rendered"
PYTHON_BIN="${PYTHON_BIN:-python3}"
"$PYTHON_BIN" - "$PROJECT_ROOT" <<'EOF'
import sys

import yaml

root = sys.argv[1]
src = f"{root}/infrastructure/kubernetes/governance/image-signature-policy.yaml"
dst = f"{root}/tests/policies/image-audit/rendered/audit-policy.yaml"

with open(src) as f:
    docs = [d for d in yaml.safe_load_all(f) if d]
audit = [d for d in docs if d["metadata"]["name"] == "audit-unsigned-images"]
assert audit, f"audit-unsigned-images not found in {src}"
with open(dst, "w") as f:
    yaml.safe_dump(audit[0], f, sort_keys=False)
EOF

kyverno test "${POLICY_TESTS}/model-registry"
kyverno test "${POLICY_TESTS}/image-audit"
kyverno test "${POLICY_TESTS}/image-tags"

echo "All policy tests passed"
