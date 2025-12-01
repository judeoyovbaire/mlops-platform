"""
Example ML Training Pipeline using Kubeflow Pipelines

This pipeline demonstrates:
1. Data loading and validation
2. Feature engineering
3. Model training with MLflow tracking
4. Model evaluation
5. Model registration with MLflow 3.x aliases
"""

from kfp import dsl
from kfp.dsl import component, Input, Output, Dataset, Model, Metrics


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn", "mlflow>=3.0.0"]
)
def load_data(
    dataset_url: str,
    output_data: Output[Dataset]
):
    """Load data from source with error handling."""
    import pandas as pd
    import sys

    try:
        df = pd.read_csv(dataset_url)
        if df.empty:
            print("Warning: Loaded dataset is empty", file=sys.stderr)
            sys.exit(1)
        df.to_csv(output_data.path, index=False)
        print(f"Loaded {len(df)} rows, {len(df.columns)} columns")
    except Exception as e:
        print(f"Error loading data from {dataset_url}: {e}", file=sys.stderr)
        sys.exit(1)


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn"]
)
def validate_data(
    input_data: Input[Dataset],
    output_data: Output[Dataset],
    metrics: Output[Metrics],
    min_rows: int = 10
):
    """Validate data quality with configurable thresholds."""
    import pandas as pd
    import sys

    try:
        df = pd.read_csv(input_data.path)

        # Basic validation
        null_counts = df.isnull().sum().sum()
        row_count = len(df)

        metrics.log_metric("null_count", int(null_counts))
        metrics.log_metric("row_count", row_count)
        metrics.log_metric("column_count", len(df.columns))

        # Remove nulls
        df_clean = df.dropna()
        rows_removed = row_count - len(df_clean)
        metrics.log_metric("rows_removed", rows_removed)

        if len(df_clean) < min_rows:
            print(f"Error: Dataset has only {len(df_clean)} rows after cleaning, minimum required: {min_rows}", file=sys.stderr)
            sys.exit(1)

        df_clean.to_csv(output_data.path, index=False)
        print(f"Validation complete. Removed {rows_removed} rows with nulls. Final: {len(df_clean)} rows")

    except Exception as e:
        print(f"Error validating data: {e}", file=sys.stderr)
        sys.exit(1)


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn"]
)
def feature_engineering(
    input_data: Input[Dataset],
    output_data: Output[Dataset],
    target_column: str
):
    """Perform feature engineering with error handling."""
    import pandas as pd
    from sklearn.preprocessing import StandardScaler
    import sys

    try:
        df = pd.read_csv(input_data.path)

        if target_column not in df.columns:
            print(f"Error: Target column '{target_column}' not found in dataset. Available columns: {list(df.columns)}", file=sys.stderr)
            sys.exit(1)

        # Separate features and target
        X = df.drop(columns=[target_column])
        y = df[target_column]

        # Only scale numerical columns
        numeric_cols = X.select_dtypes(include=['float64', 'int64']).columns
        if len(numeric_cols) == 0:
            print("Warning: No numeric columns found for scaling")
            df_processed = df.copy()
        else:
            scaler = StandardScaler()
            X_scaled = pd.DataFrame(
                scaler.fit_transform(X[numeric_cols]),
                columns=numeric_cols,
                index=X.index
            )
            # Keep non-numeric columns as-is
            for col in X.columns:
                if col not in numeric_cols:
                    X_scaled[col] = X[col]

            df_processed = X_scaled.copy()
            df_processed[target_column] = y.values

        df_processed.to_csv(output_data.path, index=False)
        print(f"Feature engineering complete. Shape: {df_processed.shape}")

    except Exception as e:
        print(f"Error in feature engineering: {e}", file=sys.stderr)
        sys.exit(1)


@component(
    base_image="python:3.10-slim",
    packages_to_install=["pandas", "scikit-learn", "mlflow>=3.0.0", "boto3"]
)
def train_model(
    input_data: Input[Dataset],
    target_column: str,
    model_name: str,
    mlflow_tracking_uri: str,
    n_estimators: int,
    max_depth: int,
    test_size: float,
    output_model: Output[Model],
    metrics: Output[Metrics]
):
    """Train model with MLflow tracking and configurable hyperparameters."""
    import pandas as pd
    import mlflow
    from sklearn.model_selection import train_test_split
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score
    import joblib
    import sys

    try:
        # Set MLflow tracking
        mlflow.set_tracking_uri(mlflow_tracking_uri)
        mlflow.set_experiment(model_name)

        # Load data
        df = pd.read_csv(input_data.path)
        X = df.drop(columns=[target_column])
        y = df[target_column]

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42, stratify=y
        )

        # Train model with MLflow tracking
        with mlflow.start_run() as run:
            # Hyperparameters
            params = {
                "n_estimators": n_estimators,
                "max_depth": max_depth,
                "random_state": 42,
                "n_jobs": -1
            }
            mlflow.log_params(params)
            mlflow.log_param("test_size", test_size)

            # Train
            model = RandomForestClassifier(**params)
            model.fit(X_train, y_train)

            # Evaluate
            y_pred = model.predict(X_test)
            accuracy = accuracy_score(y_test, y_pred)
            f1 = f1_score(y_test, y_pred, average='weighted')
            precision = precision_score(y_test, y_pred, average='weighted')
            recall = recall_score(y_test, y_pred, average='weighted')

            # Log metrics to MLflow
            mlflow.log_metric("accuracy", accuracy)
            mlflow.log_metric("f1_score", f1)
            mlflow.log_metric("precision", precision)
            mlflow.log_metric("recall", recall)

            # Log model with signature
            mlflow.sklearn.log_model(
                model,
                "model",
                input_example=X_train.head(1)
            )

            # Save model locally for pipeline artifact
            joblib.dump(model, output_model.path)

            # Log to Kubeflow metrics
            metrics.log_metric("accuracy", accuracy)
            metrics.log_metric("f1_score", f1)
            metrics.log_metric("precision", precision)
            metrics.log_metric("recall", recall)
            metrics.log_metric("run_id", run.info.run_id)

            print(f"Training complete. Run ID: {run.info.run_id}")
            print(f"Accuracy: {accuracy:.4f}, F1: {f1:.4f}, Precision: {precision:.4f}, Recall: {recall:.4f}")

    except Exception as e:
        print(f"Error training model: {e}", file=sys.stderr)
        sys.exit(1)


@component(
    base_image="python:3.10-slim",
    packages_to_install=["mlflow>=3.0.0", "boto3"]
)
def register_model(
    model: Input[Model],
    model_name: str,
    mlflow_tracking_uri: str,
    accuracy_threshold: float,
    alias: str = "champion"
):
    """Register model using MLflow 3.x aliases (replaces deprecated stages API)."""
    import mlflow
    from mlflow.tracking import MlflowClient
    import sys

    try:
        mlflow.set_tracking_uri(mlflow_tracking_uri)
        client = MlflowClient()

        # Get latest run
        experiment = client.get_experiment_by_name(model_name)
        if experiment is None:
            print(f"Error: Experiment '{model_name}' not found", file=sys.stderr)
            sys.exit(1)

        runs = client.search_runs(
            experiment_ids=[experiment.experiment_id],
            order_by=["metrics.accuracy DESC"],
            max_results=1
        )

        if not runs:
            print("No runs found in experiment", file=sys.stderr)
            sys.exit(1)

        best_run = runs[0]
        accuracy = best_run.data.metrics.get("accuracy", 0)

        if accuracy >= accuracy_threshold:
            # Register model
            model_uri = f"runs:/{best_run.info.run_id}/model"
            registered_model = mlflow.register_model(model_uri, model_name)
            print(f"Model registered: {registered_model.name} version {registered_model.version}")

            # Use MLflow 3.x aliases instead of deprecated stages
            # Aliases replace stages (Staging, Production, Archived)
            client.set_registered_model_alias(
                name=model_name,
                alias=alias,
                version=registered_model.version
            )
            print(f"Model alias '{alias}' set for version {registered_model.version}")

            # Add description and tags for better traceability
            client.update_model_version(
                name=model_name,
                version=registered_model.version,
                description=f"Accuracy: {accuracy:.4f}, trained from run {best_run.info.run_id}"
            )
        else:
            print(f"Model accuracy {accuracy:.4f} below threshold {accuracy_threshold}. Not registering.")

    except Exception as e:
        print(f"Error registering model: {e}", file=sys.stderr)
        sys.exit(1)


@dsl.pipeline(
    name="ML Training Pipeline",
    description="End-to-end ML training pipeline with MLflow 3.x tracking and model aliases"
)
def ml_training_pipeline(
    dataset_url: str = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv",
    target_column: str = "species",
    model_name: str = "iris-classifier",
    mlflow_tracking_uri: str = "http://mlflow.mlflow.svc.cluster.local:5000",
    accuracy_threshold: float = 0.9,
    # Configurable hyperparameters
    n_estimators: int = 100,
    max_depth: int = 10,
    test_size: float = 0.2,
    min_validation_rows: int = 10,
    model_alias: str = "champion"
):
    """ML Training Pipeline with configurable hyperparameters."""

    # Step 1: Load data
    load_task = load_data(dataset_url=dataset_url)

    # Step 2: Validate data
    validate_task = validate_data(
        input_data=load_task.outputs["output_data"],
        min_rows=min_validation_rows
    )

    # Step 3: Feature engineering
    feature_task = feature_engineering(
        input_data=validate_task.outputs["output_data"],
        target_column=target_column
    )

    # Step 4: Train model with configurable hyperparameters
    train_task = train_model(
        input_data=feature_task.outputs["output_data"],
        target_column=target_column,
        model_name=model_name,
        mlflow_tracking_uri=mlflow_tracking_uri,
        n_estimators=n_estimators,
        max_depth=max_depth,
        test_size=test_size
    )

    # Step 5: Register model with alias
    register_model(
        model=train_task.outputs["output_model"],
        model_name=model_name,
        mlflow_tracking_uri=mlflow_tracking_uri,
        accuracy_threshold=accuracy_threshold,
        alias=model_alias
    )


if __name__ == "__main__":
    from kfp import compiler

    compiler.Compiler().compile(
        pipeline_func=ml_training_pipeline,
        package_path="ml_training_pipeline.yaml"
    )
    print("Pipeline compiled to ml_training_pipeline.yaml")