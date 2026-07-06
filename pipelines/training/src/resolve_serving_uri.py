"""
Resolve a registered MLflow model alias to its serving artifact URI.

This is the link between the model registry and KServe: given a model name
and alias (e.g. iris-classifier @ champion), it returns the storage URI of
that exact version's artifacts so an InferenceService can serve it. The CI
deploy workflow renders the champion InferenceService template from this
output — promoting a different version in the registry changes what the next
deploy serves, with full run/version traceability.
"""

import argparse
import json
import sys
from dataclasses import asdict, dataclass

from mlflow.exceptions import MlflowException, RestException
from mlflow.tracking import MlflowClient

from pipelines.shared.exceptions import ModelRegistrationError
from pipelines.shared.logging_utils import get_logger
from pipelines.shared.mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout

logger = get_logger(__name__)

# Storage schemes the KServe storage-initializer can fetch directly.
FETCHABLE_SCHEMES = ("s3://", "gs://", "abs://", "https://", "http://", "pvc://")


@dataclass
class ResolvedServingModel:
    """Resolution result for a registry alias."""

    model_name: str
    alias: str
    version: int
    run_id: str
    experiment_id: str
    storage_uri: str


def resolve_serving_uri(
    model_name: str,
    alias: str,
    mlflow_uri: str,
    mlflow_timeout_seconds: int = MLFLOW_CONNECTION_TIMEOUT,
) -> ResolvedServingModel:
    """Resolve model_name@alias to the artifact URI KServe should serve.

    Args:
        model_name: Registered model name (e.g. "iris-classifier").
        alias: Registry alias (e.g. "champion").
        mlflow_uri: MLflow tracking server URI.
        mlflow_timeout_seconds: Connection timeout.

    Returns:
        ResolvedServingModel with the version, run id, and storage URI.

    Raises:
        ModelRegistrationError: If the alias does not resolve, or resolves to
            a URI the KServe storage-initializer cannot fetch.
    """

    def _connect() -> MlflowClient:
        import mlflow

        mlflow.set_tracking_uri(mlflow_uri)
        return MlflowClient()

    client: MlflowClient = run_with_timeout(
        _connect,
        seconds=mlflow_timeout_seconds,
        error_message=f"MLflow connection timed out after {mlflow_timeout_seconds}s",
    )

    try:
        mv = client.get_model_version_by_alias(model_name, alias)
    except (RestException, MlflowException) as e:
        raise ModelRegistrationError(
            f"Could not resolve '{model_name}@{alias}': {e}. "
            f"Check: 1) the model is registered (run the training pipeline), "
            f"2) the alias '{alias}' is assigned (register_model sets it after "
            f"the accuracy gate), 3) MLflow UI -> Models -> {model_name}."
        ) from e

    source = mv.source or ""
    if not source.startswith(FETCHABLE_SCHEMES):
        raise ModelRegistrationError(
            f"'{model_name}@{alias}' (version {mv.version}) resolves to "
            f"'{source}', which the KServe storage-initializer cannot fetch. "
            f"This usually means MLflow runs with proxied artifacts "
            f"(mlflow-artifacts:/ scheme) instead of a direct S3 artifact "
            f"root. The platform's MLflow chart is configured with a direct "
            f"s3:// artifactRoot - check mlflow-values.yaml."
        )

    # Lineage: governance policy requires the experiment id on the deployed
    # service; the model version only carries the run id, so look it up.
    experiment_id = ""
    if mv.run_id:
        try:
            experiment_id = client.get_run(mv.run_id).info.experiment_id or ""
        except (RestException, MlflowException) as e:
            logger.warning(f"Could not fetch run {mv.run_id} for experiment id: {e}")

    resolved = ResolvedServingModel(
        model_name=model_name,
        alias=alias,
        version=int(mv.version),
        run_id=mv.run_id or "",
        experiment_id=experiment_id,
        storage_uri=source,
    )
    logger.info(
        f"Resolved {model_name}@{alias} -> version {resolved.version}, "
        f"run {resolved.run_id}, uri {resolved.storage_uri}"
    )
    return resolved


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Resolve registry alias to serving URI")
    parser.add_argument("--model-name", required=True, help="Registered model name")
    parser.add_argument("--alias", default="champion", help="Registry alias (default: champion)")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument(
        "--output",
        default=None,
        help="Optional path to write the resolution as JSON",
    )
    parser.add_argument(
        "--github-env",
        default=None,
        help=(
            "Optional path (typically $GITHUB_ENV) to append "
            "MODEL_STORAGE_URI/MODEL_VERSION/MODEL_RUN_ID/MODEL_NAME exports"
        ),
    )

    args = parser.parse_args()

    try:
        result = resolve_serving_uri(args.model_name, args.alias, args.mlflow_uri)
    except ModelRegistrationError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(asdict(result), indent=2))

    if args.output:
        with open(args.output, "w") as f:
            json.dump(asdict(result), f)

    if args.github_env:
        with open(args.github_env, "a") as f:
            f.write(f"MODEL_NAME={result.model_name}\n")
            f.write(f"MODEL_STORAGE_URI={result.storage_uri}\n")
            f.write(f"MODEL_VERSION={result.version}\n")
            f.write(f"MODEL_RUN_ID={result.run_id}\n")
            f.write(f"MODEL_EXPERIMENT_ID={result.experiment_id}\n")
