"""
Unit tests for the Iris Classifier training logic.

Tests cover:
- Data loading and preprocessing
- Model training
- Model evaluation
- Edge cases and error handling
"""

import pytest
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split


# =============================================================================
# Training Functions (self-contained for testing)
# =============================================================================

def load_data(url: str) -> pd.DataFrame:
    """Load dataset from URL."""
    df = pd.read_csv(url)
    return df


def preprocess_data(df: pd.DataFrame, target_column: str):
    """Preprocess data: encode labels and scale features."""
    X = df.drop(columns=[target_column])
    y = df[target_column]

    label_encoder = LabelEncoder()
    y_encoded = label_encoder.fit_transform(y)

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
    return {
        "accuracy": accuracy_score(y_test, y_pred),
        "f1_score": f1_score(y_test, y_pred, average='weighted')
    }


# =============================================================================
# Test Classes
# =============================================================================

class TestLoadData:
    """Tests for data loading functionality."""

    def test_load_data_from_url(self):
        """Test loading data from a valid URL."""
        url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
        df = load_data(url)

        assert isinstance(df, pd.DataFrame)
        assert len(df) == 150
        assert 'species' in df.columns
        assert len(df.columns) == 5

    def test_load_data_columns(self):
        """Test that loaded data has expected columns."""
        url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
        df = load_data(url)

        expected_columns = ['sepal_length', 'sepal_width', 'petal_length', 'petal_width', 'species']
        assert list(df.columns) == expected_columns

    def test_load_data_no_nulls(self):
        """Test that loaded data has no null values."""
        url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
        df = load_data(url)

        assert df.isnull().sum().sum() == 0


class TestPreprocessData:
    """Tests for data preprocessing functionality."""

    def test_preprocess_returns_correct_types(self, iris_dataframe):
        """Test that preprocessing returns correct types."""
        X, y, label_encoder, scaler = preprocess_data(iris_dataframe, "species")

        assert isinstance(X, np.ndarray)
        assert isinstance(y, np.ndarray)
        assert isinstance(label_encoder, LabelEncoder)
        assert isinstance(scaler, StandardScaler)

    def test_preprocess_shapes(self, iris_dataframe):
        """Test that preprocessing returns correct shapes."""
        X, y, label_encoder, scaler = preprocess_data(iris_dataframe, "species")

        assert X.shape == (150, 4)  # 150 samples, 4 features
        assert y.shape == (150,)    # 150 labels

    def test_preprocess_label_encoding(self, iris_dataframe):
        """Test that labels are correctly encoded."""
        X, y, label_encoder, scaler = preprocess_data(iris_dataframe, "species")

        # Labels should be 0, 1, 2
        assert set(y) == {0, 1, 2}
        # Should be able to decode back
        assert set(label_encoder.classes_) == {'setosa', 'versicolor', 'virginica'}

    def test_preprocess_scaling(self, iris_dataframe):
        """Test that features are properly scaled."""
        X, y, label_encoder, scaler = preprocess_data(iris_dataframe, "species")

        # After StandardScaler, mean should be ~0 and std ~1
        assert np.abs(X.mean()) < 0.1
        assert np.abs(X.std() - 1.0) < 0.1


class TestTrainModel:
    """Tests for model training functionality."""

    def test_train_model_returns_classifier(self, iris_dataframe):
        """Test that training returns a RandomForestClassifier."""
        X, y, _, _ = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=10, max_depth=5)

        assert isinstance(model, RandomForestClassifier)

    def test_train_model_can_predict(self, iris_dataframe, sample_features):
        """Test that trained model can make predictions."""
        X, y, _, scaler = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=10, max_depth=5)

        # Scale the sample features
        sample_scaled = scaler.transform(sample_features)
        prediction = model.predict(sample_scaled)

        assert len(prediction) == 1
        assert prediction[0] in [0, 1, 2]

    def test_train_model_hyperparameters(self, iris_dataframe):
        """Test that hyperparameters are correctly applied."""
        X, y, _, _ = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=50, max_depth=3)

        assert model.n_estimators == 50
        assert model.max_depth == 3

    def test_train_model_deterministic(self, iris_dataframe):
        """Test that training with same seed produces same results."""
        X, y, _, _ = preprocess_data(iris_dataframe, "species")

        model1 = train_model(X, y, n_estimators=10, max_depth=5, random_state=42)
        model2 = train_model(X, y, n_estimators=10, max_depth=5, random_state=42)

        # Predictions should be identical
        pred1 = model1.predict(X[:5])
        pred2 = model2.predict(X[:5])
        np.testing.assert_array_equal(pred1, pred2)


class TestEvaluateModel:
    """Tests for model evaluation functionality."""

    def test_evaluate_returns_metrics(self, iris_dataframe):
        """Test that evaluation returns expected metrics."""
        X, y, label_encoder, _ = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=10, max_depth=5)
        metrics = evaluate_model(model, X, y, label_encoder)

        assert 'accuracy' in metrics
        assert 'f1_score' in metrics

    def test_evaluate_metrics_range(self, iris_dataframe):
        """Test that metrics are in valid range [0, 1]."""
        X, y, label_encoder, _ = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=100, max_depth=10)
        metrics = evaluate_model(model, X, y, label_encoder)

        assert 0.0 <= metrics['accuracy'] <= 1.0
        assert 0.0 <= metrics['f1_score'] <= 1.0

    def test_evaluate_high_accuracy(self, iris_dataframe):
        """Test that a well-trained model achieves high accuracy."""
        X, y, label_encoder, _ = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=100, max_depth=10)
        metrics = evaluate_model(model, X, y, label_encoder)

        # Iris is easy - should get > 90% accuracy on training data
        assert metrics['accuracy'] > 0.9


class TestEndToEnd:
    """End-to-end integration tests."""

    def test_full_pipeline(self):
        """Test the full training pipeline."""
        # Load
        url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
        df = load_data(url)

        # Preprocess
        X, y, label_encoder, scaler = preprocess_data(df, "species")

        # Split
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )

        # Train
        model = train_model(X_train, y_train, n_estimators=50, max_depth=5)

        # Evaluate
        metrics = evaluate_model(model, X_test, y_test, label_encoder)

        # Assert good performance
        assert metrics['accuracy'] > 0.9
        assert metrics['f1_score'] > 0.9

    def test_batch_prediction(self, iris_dataframe, sample_batch_features):
        """Test batch prediction capability."""
        X, y, label_encoder, scaler = preprocess_data(iris_dataframe, "species")
        model = train_model(X, y, n_estimators=50, max_depth=5)

        # Scale batch features
        batch_scaled = scaler.transform(sample_batch_features)
        predictions = model.predict(batch_scaled)

        assert len(predictions) == 3
        assert all(p in [0, 1, 2] for p in predictions)
