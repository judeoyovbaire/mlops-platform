"""Run the canary AnalysisTemplate as a standalone AnalysisRun and act on it.

The ADR-016 brain, adjusted to VERIFIED RawDeployment behavior: KServe
ignores canaryTrafficPercent in RawDeployment mode (a challenger rollout
is a plain rolling update - confirmed live 2026-07-13). The mechanism is
therefore post-deploy verification with automated rollback:

  deploy challenger (full rollout) -> this analysis judges it under real
  traffic -> Failed => patch storageUri back to the stable champion
  (--rollback-uri), exit 1 -> Successful => keep it, exit 0.

A true traffic-split canary needs two InferenceServices behind weighted
ALB target groups - recorded in ADR-016 as the follow-up.

Usage:
  python run-canary-analysis.py --service-name iris-classifier \
      --rollback-uri s3://bucket/1/<champion-run>/artifacts/serving_model \
      [--canary-pods-regex 'iris-classifier-predictor-.*'] [--no-act]
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = (
    REPO_ROOT / "infrastructure" / "kubernetes" / "progressive-delivery" / "analysis-template.yaml"
)


def kubectl(*args: str, input_data: str | None = None) -> str:
    result = subprocess.run(
        ["kubectl", *args],
        input=input_data,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def render_analysis_run(service_name: str, canary_pods_regex: str, run_name: str) -> dict:
    docs = [d for d in yaml.safe_load_all(TEMPLATE.read_text()) if d]
    template = next(d for d in docs if d.get("kind") == "AnalysisTemplate")

    args = {"service-name": service_name, "canary-pods-regex": canary_pods_regex}
    raw = yaml.safe_dump(template["spec"]["metrics"])
    for key, value in args.items():
        raw = raw.replace("{{args." + key + "}}", value)
    unresolved = re.findall(r"\{\{args\.[^}]+\}\}", raw)
    if unresolved:
        raise SystemExit(f"Unresolved template args: {unresolved}")

    return {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "AnalysisRun",
        "metadata": {"name": run_name, "namespace": "mlops"},
        "spec": {"metrics": yaml.safe_load(raw)},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--service-name", required=True)
    parser.add_argument(
        "--canary-pods-regex",
        default=None,
        help="Pod regex selecting canary pods (default: template default)",
    )
    parser.add_argument(
        "--rollback-uri",
        default=None,
        help="Champion storageUri to restore on a Failed verdict",
    )
    parser.add_argument(
        "--no-act",
        action="store_true",
        help="Only report the verdict; do not roll back or promote",
    )
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    regex = args.canary_pods_regex or f"{args.service_name}-predictor-.*"
    run_name = f"canary-{args.service_name}-{int(time.time())}"

    run = render_analysis_run(args.service_name, regex, run_name)
    kubectl("create", "-f", "-", input_data=json.dumps(run))
    print(f"AnalysisRun created: {run_name} (canary pods: {regex})")

    deadline = time.time() + args.timeout
    phase = "Pending"
    while time.time() < deadline:
        phase = kubectl(
            "get", "analysisrun", run_name, "-n", "mlops", "-o", "jsonpath={.status.phase}"
        )
        if phase in ("Successful", "Failed", "Error", "Inconclusive"):
            break
        time.sleep(15)

    measurements = kubectl(
        "get",
        "analysisrun",
        run_name,
        "-n",
        "mlops",
        "-o",
        "jsonpath={range .status.metricResults[*]}{.name}: {.phase} ({.measurements[-1:].value}){'\\n'}{end}",
    )
    print(f"Verdict: {phase}\n{measurements}")

    if args.no_act:
        return 0 if phase == "Successful" else 1

    if phase == "Successful":
        print("VERIFIED: challenger stays (verdict Successful)")
        return 0

    # Any non-success verdict rolls back - the challenger must prove itself.
    if not args.rollback_uri:
        print("Verdict was not Successful and no --rollback-uri given", file=sys.stderr)
        return 1
    kubectl(
        "patch",
        "inferenceservice",
        args.service_name,
        "-n",
        "mlops",
        "--type=merge",
        "-p",
        json.dumps({"spec": {"predictor": {"model": {"storageUri": args.rollback_uri}}}}),
    )
    print(f"ROLLED BACK to {args.rollback_uri} (verdict was {phase})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
