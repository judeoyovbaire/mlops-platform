import argparse
import sys

import mlflow
from mlflow.tracking import MlflowClient


def register_model(model_name, mlflow_uri, threshold, alias, run_id):
    try:
        mlflow.set_tracking_uri(mlflow_uri)
        client = MlflowClient()

        # Get run metrics
        run = client.get_run(run_id)
        # Handle cases where metrics might be missing or keys differ
        accuracy = run.data.metrics.get("accuracy", 0)

        print(f"Checking model from Run ID: {run_id}")
        print(f"Model accuracy: {accuracy:.4f}, threshold: {threshold}")

        if accuracy >= threshold:
            # Register model
            model_uri = f"runs:/{run_id}/model"
            mv = mlflow.register_model(model_uri, model_name)
            print(f"Registered {model_name} version {mv.version}")

            # Set alias (MLflow 3.x)
            client.set_registered_model_alias(model_name, alias, mv.version)
            print(f"Set alias {alias} -> version {mv.version}")
        else:
            print(f"Accuracy {accuracy:.4f} below threshold {threshold}, not registering")

    except Exception as e:
        print(f"Registration error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Register model")
    parser.add_argument("--model-name", required=True, help="Model name")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")
    parser.add_argument("--threshold", type=float, required=True, help="Accuracy threshold")
    parser.add_argument("--alias", required=True, help="Model alias (e.g., champion)")
    parser.add_argument("--run-id", required=True, help="MLflow Run ID")

    args = parser.parse_args()

    register_model(args.model_name, args.mlflow_uri, args.threshold, args.alias, args.run_id)
