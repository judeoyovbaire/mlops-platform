"""Register a deliberately degraded challenger version for the rollback demo.

The JDH-372 demo needs a canary that fails under real traffic. This logs a
pyfunc that raises on every predict - the serving pod comes up healthy
(load succeeds, readiness passes) but every inference returns 5xx, so the
canary AnalysisRun's error-rate gate fires and the automated rollback
triggers.

The point of the demo: a model can pass every cheap gate (it loads, it
has lineage, admission admits it) and still be broken under traffic -
metric-driven canary analysis is the last line of defense.

Runs against a port-forwarded MLflow (http://localhost:5000). Registers as
the NEXT version of the given model and tags it clearly as the demo
challenger. It deliberately does NOT touch the champion alias.

Usage:
  kubectl port-forward -n mlflow svc/mlflow 5000:5000 &
  python register-degraded-challenger.py --model-name iris-classifier
"""

import argparse

import mlflow
import mlflow.pyfunc
import pandas as pd


class DegradedModel(mlflow.pyfunc.PythonModel):
    """Loads fine, fails on every prediction - the canary-killer."""

    def predict(self, context, model_input, params=None):
        raise ValueError(
            "DEMO degradation: this challenger fails on every prediction "
            "(registered by scripts/demo/register-degraded-challenger.py)"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-name", default="iris-classifier")
    parser.add_argument("--mlflow-uri", default="http://localhost:5000")
    args = parser.parse_args()

    mlflow.set_tracking_uri(args.mlflow_uri)
    mlflow.set_experiment("rollback-demo")

    input_example = pd.DataFrame(
        {
            "sepal_length": [5.1],
            "sepal_width": [3.5],
            "petal_length": [1.4],
            "petal_width": [0.2],
        }
    )

    with mlflow.start_run(run_name="degraded-challenger") as run:
        mlflow.log_param("demo", "jdh-372-rollback")
        mlflow.log_param("degradation", "raises-on-predict")
        # Logged WITHOUT an input-example inference (the model raises), so
        # pass the example only for signature documentation.
        mlflow.pyfunc.log_model(
            artifact_path="serving_model",
            python_model=DegradedModel(),
            input_example=input_example,
        )

    mv = mlflow.register_model(f"runs:/{run.info.run_id}/serving_model", args.model_name)
    client = mlflow.MlflowClient()
    client.set_model_version_tag(args.model_name, mv.version, "demo", "degraded-challenger")
    client.set_registered_model_alias(args.model_name, "challenger", mv.version)

    print(
        f"Registered degraded challenger: {args.model_name} v{mv.version} "
        f"(alias 'challenger', run {run.info.run_id})"
    )
    print(f"storageUri: runs artifact path serving_model of run {run.info.run_id}")


if __name__ == "__main__":
    main()
