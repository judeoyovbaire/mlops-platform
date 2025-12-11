"""
Pytest configuration and shared fixtures for MLOps Platform tests.
"""

import pytest
import pandas as pd
import numpy as np
from sklearn.datasets import load_iris


@pytest.fixture
def iris_dataframe():
    """Load iris dataset as a pandas DataFrame."""
    iris = load_iris()
    df = pd.DataFrame(
        data=np.c_[iris['data'], iris['target']],
        columns=iris['feature_names'] + ['target']
    )
    # Convert target to species names for consistency with CSV format
    df['species'] = df['target'].map({
        0: 'setosa',
        1: 'versicolor',
        2: 'virginica'
    })
    df = df.drop(columns=['target'])
    # Rename columns to match expected format
    df.columns = ['sepal_length', 'sepal_width', 'petal_length', 'petal_width', 'species']
    return df


@pytest.fixture
def sample_features():
    """Sample feature array for testing predictions."""
    return np.array([[5.1, 3.5, 1.4, 0.2]])  # setosa


@pytest.fixture
def sample_batch_features():
    """Batch of sample features for testing."""
    return np.array([
        [5.1, 3.5, 1.4, 0.2],  # setosa
        [7.0, 3.2, 4.7, 1.4],  # versicolor
        [6.3, 3.3, 6.0, 2.5],  # virginica
    ])


@pytest.fixture
def mock_mlflow(mocker):
    """Mock MLflow for unit tests that don't need real tracking."""
    mock = mocker.patch('mlflow.set_tracking_uri')
    mocker.patch('mlflow.set_experiment')
    mocker.patch('mlflow.start_run')
    mocker.patch('mlflow.log_params')
    mocker.patch('mlflow.log_metrics')
    mocker.patch('mlflow.sklearn.log_model')
    return mock
