#!/bin/bash
set -euo pipefail

# Render Sloth PrometheusServiceLevel CRs to plain PrometheusRule manifests
# (ADR-016). The Sloth CRs in slo/ are the SOURCE format; the rendered
# rules in slo/rendered/ are what the kustomization ships - no Sloth
# operator runs in the cluster just to template three files.
#
# CI regenerates and diffs (same drift-guard pattern as the dependency
# lockfiles and the serving runtime contract): edit a source SLO without
# re-rendering and the build fails.

SLOTH_IMAGE="ghcr.io/slok/sloth:v0.11.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SLO_DIR="${PROJECT_ROOT}/infrastructure/kubernetes/slo"

mkdir -p "${SLO_DIR}/rendered"

for src in "${SLO_DIR}"/*.yaml; do
    base="$(basename "$src" .yaml)"
    [[ "$base" == "kustomization" ]] && continue
    docker run --rm -v "${SLO_DIR}:/slo" "$SLOTH_IMAGE" \
        generate -i "/slo/${base}.yaml" -o "/slo/rendered/${base}-rules.yaml" \
        --extra-labels "release=prometheus"
    echo "rendered: slo/rendered/${base}-rules.yaml"
done
