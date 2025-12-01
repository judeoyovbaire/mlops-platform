#!/usr/bin/env python3
"""
Iris Classifier Training Script

This script demonstrates:
1. Loading and preprocessing data
2. Training a RandomForest classifier
3. Logging experiments to MLflow
4. Registering the model with aliases

Usage:
    python train.py [--mlflow-uri URI] [--experiment-name NAME]
"""

import argparse
import sys

import mlflow
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, LabelEncoder


def load_data(url: str) -> pd.DataFrame:
    """Load dataset from URL."""
    print(f"Loading data from {url}...")
    df = pd.read_csv(url)
    print(f"Loaded {len(df)} rows, {len(df.columns)} columns")
    return df


def preprocess_data(df: pd.DataFrame, target_column: str):
    """Preprocess data: encode labels and scale features."""
    # Separate features and target
    X = df.drop(columns=[target_column])
    y = df[target_column]

    # Encode target labels
    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y)

    # Scale features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    return X_scaled, y_encoded, label_encoder, scaler


def train_model(
    X_train,
    y_train,
    n_estimators: int = 100,
    max_depth: int = 10,
    random_state: int = 42
) -> RandomForestClassifier:
    """Train a RandomForest classifier."""
    model = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        random_state=random_state,
        n_jobs=-1
    )
    model.fit(X_train, y_train)
    return model


def evaluate_model(model, X_test, y_test, label_encoder):
    """Evaluate the model and return metrics."""
    y_pred = model.predict(X_test)

    accuracy = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average='weighted')

    print("\nClassification Report:")
    print(classification_report(
        y_test, y_pred,
        target_names=label_encoder.classes_
    ))

    return {
        "accuracy": accuracy,
        "f1_score": f1
    }


def main():
    parser = argparse.ArgumentParser(description="Train Iris Classifier")
    parser.add_argument(
        "--mlflow-uri",
        default="http://localhost:5000",
        help="MLflow tracking URI"
    )
    parser.add_argument(
        "--experiment-name",
        default="iris-classifier",
        help="MLflow experiment name"
    )
    parser.add_argument(
        "--dataset-url",
        default="https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv",
        help="URL to the dataset"
    )
    parser.add_argument(
        "--n-estimators",
        type=int,
        default=100,
        help="Number of trees in the forest"
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=10,
        help="Maximum depth of the trees"
    )
    parser.add_argument(
        "--test-size",
        type=float,
        default=0.2,
        help="Test set size"
    )
    parser.add_argument(
        "--register",
        action="store_true",
        help="Register model if accuracy > 0.9"
    )
    args = parser.parse_args()

    # Set MLflow tracking
    mlflow.set_tracking_uri(args.mlflow_uri)
    mlflow.set_experiment(args.experiment_name)

    print(f"MLflow tracking URI: {args.mlflow_uri}")
    print(f"Experiment: {args.experiment_name}")

    # Load data
    df = load_data(args.dataset_url)

    # Preprocess
    X, y, label_encoder, scaler = preprocess_data(df, "species")

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y,
        test_size=args.test_size,
        random_state=42,
        stratify=y
    )

    # Train with MLflow tracking
    with mlflow.start_run() as run:
        print(f"\nMLflow Run ID: {run.info.run_id}")

        # Log parameters
        params = {
            "n_estimators": args.n_estimators,
            "max_depth": args.max_depth,
            "test_size": args.test_size,
            "random_state": 42
        }
        mlflow.log_params(params)

        # Train model
        print("\nTraining model...")
        model = train_model(
            X_train, y_train,
            n_estimators=args.n_estimators,
            max_depth=args.max_depth
        )

        # Evaluate
        metrics = evaluate_model(model, X_test, y_test, label_encoder)
        mlflow.log_metrics(metrics)

        print(f"\nAccuracy: {metrics['accuracy']:.4f}")
        print(f"F1 Score: {metrics['f1_score']:.4f}")

        # Log model with signature
        mlflow.sklearn.log_model(
            model,
            "model",
            input_example=X_test[:1]
        )

        # Register model if requested and accuracy is good
        if args.register and metrics['accuracy'] >= 0.9:
            print("\nRegistering model...")
            model_uri = f"runs:/{run.info.run_id}/model"
            registered_model = mlflow.register_model(
                model_uri,
                args.experiment_name
            )

            # Set alias using MLflow 3.x API
            client = mlflow.tracking.MlflowClient()
            client.set_registered_model_alias(
                name=args.experiment_name,
                alias="champion",
                version=registered_model.version
            )
            print(f"Model registered as '{args.experiment_name}' version {registered_model.version}")
            print("Alias 'champion' set for this version")
        elif args.register:
            print(f"\nModel accuracy ({metrics['accuracy']:.4f}) below threshold (0.9)")
            print("Model not registered")

    print("\nTraining complete!")
    return 0


if __name__ == "__main__":
    sys.exit(main())