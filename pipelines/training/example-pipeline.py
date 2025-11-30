"""
Example ML Training Pipeline using Kubeflow Pipelines

This pipeline demonstrates:
1. Data loading and validation
2. Feature engineering
3. Model training with MLflow tracking
4. Model evaluation
5. Model registration
"""

from kfp import dsl
from kfp.dsl import component, Input, Output, Dataset, Model, Metrics


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn", "mlflow"]
)
def load_data(
    dataset_url: str,
    output_data: Output[Dataset]
):
    """Load data from source."""
    import pandas as pd

    df = pd.read_csv(dataset_url)
    df.to_csv(output_data.path, index=False)
    print(f"Loaded {len(df)} rows")


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn"]
)
def validate_data(
    input_data: Input[Dataset],
    output_data: Output[Dataset],
    metrics: Output[Metrics]
):
    """Validate data quality."""
    import pandas as pd

    df = pd.read_csv(input_data.path)

    # Basic validation
    null_counts = df.isnull().sum().sum()
    row_count = len(df)

    metrics.log_metric("null_count", null_counts)
    metrics.log_metric("row_count", row_count)

    # Remove nulls
    df_clean = df.dropna()
    df_clean.to_csv(output_data.path, index=False)

    print(f"Validation complete. Removed {row_count - len(df_clean)} rows with nulls")


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn"]
)
def feature_engineering(
    input_data: Input[Dataset],
    output_data: Output[Dataset],
    target_column: str
):
    """Perform feature engineering."""
    import pandas as pd
    from sklearn.preprocessing import StandardScaler

    df = pd.read_csv(input_data.path)

    # Separate features and target
    X = df.drop(columns=[target_column])
    y = df[target_column]

    # Scale numerical features
    scaler = StandardScaler()
    X_scaled = pd.DataFrame(
        scaler.fit_transform(X),
        columns=X.columns
    )

    # Combine back
    df_processed = X_scaled.copy()
    df_processed[target_column] = y.values

    df_processed.to_csv(output_data.path, index=False)
    print(f"Feature engineering complete. Shape: {df_processed.shape}")


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn", "mlflow", "boto3"]
)
def train_model(
    input_data: Input[Dataset],
    target_column: str,
    model_name: str,
    mlflow_tracking_uri: str,
    output_model: Output[Model],
    metrics: Output[Metrics]
):
    """Train model with MLflow tracking."""
    import pandas as pd
    import mlflow
    from sklearn.model_selection import train_test_split
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, f1_score
    import joblib

    # Set MLflow tracking
    mlflow.set_tracking_uri(mlflow_tracking_uri)
    mlflow.set_experiment(model_name)

    # Load data
    df = pd.read_csv(input_data.path)
    X = df.drop(columns=[target_column])
    y = df[target_column]

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    # Train model with MLflow tracking
    with mlflow.start_run():
        # Hyperparameters
        params = {
            "n_estimators": 100,
            "max_depth": 10,
            "random_state": 42
        }
        mlflow.log_params(params)

        # Train
        model = RandomForestClassifier(**params)
        model.fit(X_train, y_train)

        # Evaluate
        y_pred = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        f1 = f1_score(y_test, y_pred, average='weighted')

        # Log metrics
        mlflow.log_metric("accuracy", accuracy)
        mlflow.log_metric("f1_score", f1)

        # Log model
        mlflow.sklearn.log_model(model, "model")

        # Save model locally
        joblib.dump(model, output_model.path)

        metrics.log_metric("accuracy", accuracy)
        metrics.log_metric("f1_score", f1)

        print(f"Training complete. Accuracy: {accuracy:.4f}, F1: {f1:.4f}")


@component(
    base_image="python:3.10-slim",
    packages_to_install=["mlflow", "boto3"]
)
def register_model(
    model: Input[Model],
    model_name: str,
    mlflow_tracking_uri: str,
    accuracy_threshold: float
):
    """Register model if it meets threshold."""
    import mlflow
    from mlflow.tracking import MlflowClient

    mlflow.set_tracking_uri(mlflow_tracking_uri)
    client = MlflowClient()

    # Get latest run
    experiment = client.get_experiment_by_name(model_name)
    runs = client.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=["metrics.accuracy DESC"],
        max_results=1
    )

    if runs:
        best_run = runs[0]
        accuracy = best_run.data.metrics.get("accuracy", 0)

        if accuracy >= accuracy_threshold:
            # Register model
            model_uri = f"runs:/{best_run.info.run_id}/model"
            registered_model = mlflow.register_model(model_uri, model_name)
            print(f"Model registered: {registered_model.name} version {registered_model.version}")

            # Transition to staging
            client.transition_model_version_stage(
                name=model_name,
                version=registered_model.version,
                stage="Staging"
            )
            print(f"Model transitioned to Staging")
        else:
            print(f"Model accuracy {accuracy:.4f} below threshold {accuracy_threshold}")
    else:
        print("No runs found")


@dsl.pipeline(
    name="ML Training Pipeline",
    description="End-to-end ML training pipeline with MLflow tracking"
)
def ml_training_pipeline(
    dataset_url: str = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv",
    target_column: str = "species",
    model_name: str = "iris-classifier",
    mlflow_tracking_uri: str = "http://mlflow.mlflow.svc.cluster.local:5000",
    accuracy_threshold: float = 0.9
):
    """ML Training Pipeline."""

    # Step 1: Load data
    load_task = load_data(dataset_url=dataset_url)

    # Step 2: Validate data
    validate_task = validate_data(input_data=load_task.outputs["output_data"])

    # Step 3: Feature engineering
    feature_task = feature_engineering(
        input_data=validate_task.outputs["output_data"],
        target_column=target_column
    )

    # Step 4: Train model
    train_task = train_model(
        input_data=feature_task.outputs["output_data"],
        target_column=target_column,
        model_name=model_name,
        mlflow_tracking_uri=mlflow_tracking_uri
    )

    # Step 5: Register model
    register_model(
        model=train_task.outputs["output_model"],
        model_name=model_name,
        mlflow_tracking_uri=mlflow_tracking_uri,
        accuracy_threshold=accuracy_threshold
    )


if __name__ == "__main__":
    from kfp import compiler

    compiler.Compiler().compile(
        pipeline_func=ml_training_pipeline,
        package_path="ml_training_pipeline.yaml"
    )
    print("Pipeline compiled to ml_training_pipeline.yaml")
