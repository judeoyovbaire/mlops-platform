"""
Pytest configuration and shared fixtures for MLOps Platform tests.
"""

import tempfile
from pathlib import Path
from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest
from sklearn.datasets import load_iris


@pytest.fixture
def iris_dataframe():
    """Load iris dataset as a pandas DataFrame."""
    iris = load_iris()
    df = pd.DataFrame(
        data=np.c_[iris["data"], iris["target"]],
        columns=iris["feature_names"] + ["target"],
    )
    # Convert target to species names for consistency with CSV format
    df["species"] = df["target"].map({0: "setosa", 1: "versicolor", 2: "virginica"})
    df = df.drop(columns=["target"])
    # Rename columns to match expected format
    df.columns = ["sepal_length", "sepal_width", "petal_length", "petal_width", "species"]
    return df


@pytest.fixture
def sample_features():
    """Sample feature array for testing predictions."""
    return np.array([[5.1, 3.5, 1.4, 0.2]])  # setosa


@pytest.fixture
def sample_batch_features():
    """Batch of sample features for testing."""
    return np.array(
        [
            [5.1, 3.5, 1.4, 0.2],  # setosa
            [7.0, 3.2, 4.7, 1.4],  # versicolor
            [6.3, 3.3, 6.0, 2.5],  # virginica
        ]
    )


@pytest.fixture
def mock_mlflow(mocker):
    """Mock MLflow for unit tests that don't need real tracking."""
    mock = mocker.patch("mlflow.set_tracking_uri")
    mocker.patch("mlflow.set_experiment")
    mocker.patch("mlflow.start_run")
    mocker.patch("mlflow.log_params")
    mocker.patch("mlflow.log_metrics")
    mocker.patch("mlflow.sklearn.log_model")
    return mock


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def iris_csv_path(temp_dir, iris_dataframe):
    """Create a temporary CSV file with iris data."""
    csv_path = temp_dir / "iris.csv"
    iris_dataframe.to_csv(csv_path, index=False)
    return str(csv_path)


@pytest.fixture
def malformed_csv_path(temp_dir):
    """Create a malformed CSV file for negative testing."""
    csv_path = temp_dir / "malformed.csv"
    csv_path.write_text('col1,col2,col3\n1,2\n3,4,5,6\n"unclosed')
    return str(csv_path)


@pytest.fixture
def empty_csv_path(temp_dir):
    """Create an empty CSV file (headers only)."""
    csv_path = temp_dir / "empty.csv"
    csv_path.write_text("col1,col2,col3\n")
    return str(csv_path)


@pytest.fixture
def all_null_csv_path(temp_dir):
    """Create a CSV file with all null values."""
    csv_path = temp_dir / "all_null.csv"
    csv_path.write_text("col1,col2,col3\n,,\n,,\n,,\n")
    return str(csv_path)


@pytest.fixture
def csv_with_nulls_path(temp_dir):
    """Create a CSV file with some null values that can still be cleaned."""
    csv_path = temp_dir / "with_nulls.csv"
    # 15 rows total, 5 with nulls = 10 clean rows (meets minimum)
    data = """sepal_length,sepal_width,petal_length,petal_width,species
5.1,3.5,1.4,0.2,setosa
4.9,3.0,1.4,0.2,setosa
4.7,3.2,1.3,0.2,setosa
,3.1,1.5,0.2,setosa
5.0,3.6,1.4,0.2,setosa
5.4,3.9,1.7,0.4,setosa
4.6,3.4,1.4,0.3,setosa
5.0,,1.5,0.2,setosa
4.4,2.9,1.4,0.2,setosa
4.9,3.1,1.5,0.1,setosa
5.4,3.7,1.5,0.2,setosa
4.8,3.4,,0.2,setosa
4.8,3.0,1.4,0.1,setosa
4.3,3.0,1.1,0.1,setosa
5.8,4.0,1.2,,setosa
"""
    csv_path.write_text(data)
    return str(csv_path)


@pytest.fixture
def numeric_only_csv_path(temp_dir):
    """Create a CSV file with only numeric columns."""
    csv_path = temp_dir / "numeric.csv"
    data = """a,b,c,target
1.0,2.0,3.0,0
4.0,5.0,6.0,1
7.0,8.0,9.0,0
10.0,11.0,12.0,1
13.0,14.0,15.0,0
16.0,17.0,18.0,1
19.0,20.0,21.0,0
22.0,23.0,24.0,1
25.0,26.0,27.0,0
28.0,29.0,30.0,1
31.0,32.0,33.0,0
"""
    csv_path.write_text(data)
    return str(csv_path)


@pytest.fixture
def mock_mlflow_client(mocker):
    """Create a mock MLflow client for register_model tests."""
    mock_client = MagicMock()

    # Mock run with metrics
    mock_run = MagicMock()
    mock_run.data.metrics = {"accuracy": 0.95, "f1_score": 0.94}
    mock_client.get_run.return_value = mock_run

    # Mock model version
    mock_version = MagicMock()
    mock_version.version = "1"
    mocker.patch("mlflow.register_model", return_value=mock_version)

    mocker.patch("mlflow.set_tracking_uri")
    # Patch where it's used, not where it's defined
    mocker.patch(
        "pipelines.training.src.register_model.MlflowClient",
        return_value=mock_client,
    )

    return mock_client


@pytest.fixture
def mock_mlflow_client_low_accuracy(mocker):
    """Create a mock MLflow client with low accuracy for threshold tests."""
    mock_client = MagicMock()

    # Mock run with low accuracy
    mock_run = MagicMock()
    mock_run.data.metrics = {"accuracy": 0.5, "f1_score": 0.45}
    mock_client.get_run.return_value = mock_run

    mocker.patch("mlflow.set_tracking_uri")
    # Patch where it's used, not where it's defined
    mocker.patch(
        "pipelines.training.src.register_model.MlflowClient",
        return_value=mock_client,
    )

    return mock_client


@pytest.fixture
def trained_model_artifacts(temp_dir, iris_dataframe):
    """Create artifacts needed for model training tests."""
    # Save processed data
    data_path = temp_dir / "processed.csv"
    iris_dataframe.to_csv(data_path, index=False)

    # Create output paths
    model_path = temp_dir / "model.joblib"
    run_id_path = temp_dir / "run_id.txt"
    accuracy_path = temp_dir / "accuracy.txt"

    return {
        "data_path": str(data_path),
        "model_path": str(model_path),
        "run_id_path": str(run_id_path),
        "accuracy_path": str(accuracy_path),
    }