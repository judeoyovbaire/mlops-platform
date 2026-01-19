import argparse
import os
import sys

import joblib
import mlflow
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split


def train_model(
    input_path: str,
    model_output_path: str,
    target: str,
    model_name: str,
    mlflow_uri: str,
    n_estimators: int,
    max_depth: int,
    test_size: float,
    run_id_output_path: str,
    accuracy_output_path: str,
) -> None:
    try:
        # Setup MLflow
        mlflow.set_tracking_uri(mlflow_uri)
        mlflow.set_experiment(model_name)

        # Load data
        print(f"Loading data from {input_path}")
        df = pd.read_csv(input_path)
        X = df.drop(columns=[target])
        y = df[target]

        # Split
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )

        with mlflow.start_run() as run:
            print(f"Starting MLflow run: {run.info.run_id}")

            # Log params
            params = {"n_estimators": n_estimators, "max_depth": max_depth, "test_size": test_size}
            mlflow.log_params(params)
            print(f"Parameters: {params}")

            # Train
            model = RandomForestClassifier(
                n_estimators=n_estimators, max_depth=max_depth, random_state=42, n_jobs=-1
            )
            model.fit(X_train, y_train)

            # Evaluate
            y_pred = model.predict(X_test)
            accuracy = accuracy_score(y_test, y_pred)
            f1 = f1_score(y_test, y_pred, average="weighted")

            print(f"Metrics - Accuracy: {accuracy:.4f}, F1: {f1:.4f}")
            mlflow.log_metrics({"accuracy": accuracy, "f1_score": f1})

            # Log model to MLflow
            mlflow.sklearn.log_model(model, "model", input_example=X_train.head(1))

            # Save outputs locally
            os.makedirs(os.path.dirname(model_output_path), exist_ok=True)
            joblib.dump(model, model_output_path)

            # Save run ID and accuracy to files for passing to next steps
            with open(run_id_output_path, "w") as f:
                f.write(run.info.run_id)
            with open(accuracy_output_path, "w") as f:
                f.write(str(accuracy))

            print(f"Training complete. Model saved to {model_output_path}")

    except Exception as e:
        print(f"Training error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Train model")
    parser.add_argument("--input", required=True, help="Path to input CSV")
    parser.add_argument("--model-output", required=True, help="Path to save model (.joblib)")
    parser.add_argument("--run-id-output", required=True, help="Path to save run ID")
    parser.add_argument("--accuracy-output", required=True, help="Path to save accuracy")

    parser.add_argument("--target", required=True, help="Target column")
    parser.add_argument("--model-name", required=True, help="Model name for MLflow")
    parser.add_argument("--mlflow-uri", required=True, help="MLflow tracking URI")

    parser.add_argument("--n-estimators", type=int, default=100, help="Number of trees")
    parser.add_argument("--max-depth", type=int, default=10, help="Max depth of trees")
    parser.add_argument("--test-size", type=float, default=0.2, help="Test set size")

    args = parser.parse_args()

    train_model(
        args.input,
        args.model_output,
        args.target,
        args.model_name,
        args.mlflow_uri,
        args.n_estimators,
        args.max_depth,
        args.test_size,
        args.run_id_output,
        args.accuracy_output,
    )
