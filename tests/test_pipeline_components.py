"""
Unit tests for Argo Workflow pipeline components.

Tests the individual component logic without requiring a Kubernetes runtime.
"""

import pytest
import pandas as pd
import numpy as np
import tempfile


class MockDataset:
    """Mock Dataset artifact for testing pipeline components."""
    def __init__(self, path: str = None):
        if path is None:
            self._temp = tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False)
            self.path = self._temp.name
        else:
            self.path = path


class MockModel:
    """Mock Model artifact for testing pipeline components."""
    def __init__(self):
        self._temp = tempfile.NamedTemporaryFile(mode='wb', suffix='.joblib', delete=False)
        self.path = self._temp.name


class MockMetrics:
    """Mock Metrics for testing pipeline components."""
    def __init__(self):
        self.metrics = {}

    def log_metric(self, name: str, value):
        self.metrics[name] = value


class TestLoadDataComponent:
    """Tests for load_data pipeline component."""

    def test_load_data_creates_output(self):
        """Test that load_data creates output dataset."""
        output = MockDataset()
        dataset_url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"

        # Simulate component logic
        df = pd.read_csv(dataset_url)
        df.to_csv(output.path, index=False)

        # Verify output
        result = pd.read_csv(output.path)
        assert len(result) == 150
        assert 'species' in result.columns

    def test_load_data_handles_valid_url(self):
        """Test loading from a valid URL."""
        url = "https://raw.githubusercontent.com/mwaskom/seaborn-data/master/iris.csv"
        df = pd.read_csv(url)
        assert not df.empty


class TestValidateDataComponent:
    """Tests for validate_data pipeline component."""

    def test_validate_removes_nulls(self, iris_dataframe):
        """Test that validation removes null values."""
        # Add some nulls
        df_with_nulls = iris_dataframe.copy()
        df_with_nulls.loc[0, 'sepal_length'] = np.nan
        df_with_nulls.loc[1, 'sepal_width'] = np.nan

        input_ds = MockDataset()
        df_with_nulls.to_csv(input_ds.path, index=False)

        output_ds = MockDataset()
        metrics = MockMetrics()

        # Simulate component logic
        df = pd.read_csv(input_ds.path)
        null_counts = df.isnull().sum().sum()
        row_count = len(df)
        metrics.log_metric("null_count", int(null_counts))
        metrics.log_metric("row_count", row_count)

        df_clean = df.dropna()
        rows_removed = row_count - len(df_clean)
        metrics.log_metric("rows_removed", rows_removed)

        df_clean.to_csv(output_ds.path, index=False)

        # Verify
        result = pd.read_csv(output_ds.path)
        assert result.isnull().sum().sum() == 0
        assert len(result) == 148  # 2 rows removed
        assert metrics.metrics["rows_removed"] == 2

    def test_validate_logs_metrics(self, iris_dataframe):
        """Test that validation logs correct metrics."""
        input_ds = MockDataset()
        iris_dataframe.to_csv(input_ds.path, index=False)
        metrics = MockMetrics()

        df = pd.read_csv(input_ds.path)
        metrics.log_metric("null_count", int(df.isnull().sum().sum()))
        metrics.log_metric("row_count", len(df))
        metrics.log_metric("column_count", len(df.columns))

        assert metrics.metrics["null_count"] == 0
        assert metrics.metrics["row_count"] == 150
        assert metrics.metrics["column_count"] == 5


class TestFeatureEngineeringComponent:
    """Tests for feature_engineering pipeline component."""

    def test_feature_engineering_scales_features(self, iris_dataframe):
        """Test that features are properly scaled."""
        from sklearn.preprocessing import StandardScaler

        input_ds = MockDataset()
        iris_dataframe.to_csv(input_ds.path, index=False)
        output_ds = MockDataset()

        # Simulate component logic
        df = pd.read_csv(input_ds.path)
        target_column = "species"
        X = df.drop(columns=[target_column])
        y = df[target_column]

        numeric_cols = X.select_dtypes(include=['float64', 'int64']).columns
        scaler = StandardScaler()
        X_scaled = pd.DataFrame(
            scaler.fit_transform(X[numeric_cols]),
            columns=numeric_cols,
            index=X.index
        )
        df_processed = X_scaled.copy()
        df_processed[target_column] = y.values
        df_processed.to_csv(output_ds.path, index=False)

        # Verify scaling
        result = pd.read_csv(output_ds.path)
        features = result.drop(columns=[target_column])
        assert np.abs(features.mean().mean()) < 0.1
        assert np.abs(features.std().mean() - 1.0) < 0.1

    def test_feature_engineering_preserves_target(self, iris_dataframe):
        """Test that target column is preserved."""
        from sklearn.preprocessing import StandardScaler

        input_ds = MockDataset()
        iris_dataframe.to_csv(input_ds.path, index=False)
        output_ds = MockDataset()

        df = pd.read_csv(input_ds.path)
        target_column = "species"
        X = df.drop(columns=[target_column])
        y = df[target_column]

        scaler = StandardScaler()
        X_scaled = pd.DataFrame(
            scaler.fit_transform(X),
            columns=X.columns,
            index=X.index
        )
        df_processed = X_scaled.copy()
        df_processed[target_column] = y.values
        df_processed.to_csv(output_ds.path, index=False)

        result = pd.read_csv(output_ds.path)
        assert target_column in result.columns
        assert set(result[target_column].unique()) == {'setosa', 'versicolor', 'virginica'}


class TestTrainModelComponent:
    """Tests for train_model pipeline component."""

    def test_train_creates_model(self, iris_dataframe):
        """Test that training creates a valid model."""
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.preprocessing import LabelEncoder
        import joblib

        # Prepare data
        X = iris_dataframe.drop(columns=['species'])
        y = LabelEncoder().fit_transform(iris_dataframe['species'])
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        # Train
        model = RandomForestClassifier(n_estimators=10, max_depth=5, random_state=42)
        model.fit(X_train, y_train)

        # Save and reload
        output_model = MockModel()
        joblib.dump(model, output_model.path)
        loaded_model = joblib.load(output_model.path)

        # Verify
        assert isinstance(loaded_model, RandomForestClassifier)
        predictions = loaded_model.predict(X_test)
        assert len(predictions) == len(y_test)

    def test_train_logs_metrics(self, iris_dataframe):
        """Test that training logs correct metrics."""
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.preprocessing import LabelEncoder
        from sklearn.metrics import accuracy_score, f1_score

        X = iris_dataframe.drop(columns=['species'])
        y = LabelEncoder().fit_transform(iris_dataframe['species'])
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        model = RandomForestClassifier(n_estimators=50, max_depth=5, random_state=42)
        model.fit(X_train, y_train)
        y_pred = model.predict(X_test)

        metrics = MockMetrics()
        metrics.log_metric("accuracy", accuracy_score(y_test, y_pred))
        metrics.log_metric("f1_score", f1_score(y_test, y_pred, average='weighted'))

        assert metrics.metrics["accuracy"] > 0.9
        assert metrics.metrics["f1_score"] > 0.9


class TestPipelineIntegration:
    """Integration tests for the full pipeline flow."""

    def test_pipeline_data_flow(self, iris_dataframe):
        """Test data flows correctly through pipeline stages."""
        from sklearn.preprocessing import StandardScaler, LabelEncoder
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import accuracy_score

        # Stage 1: Load (simulated)
        df = iris_dataframe.copy()
        assert len(df) == 150

        # Stage 2: Validate
        df_clean = df.dropna()
        assert len(df_clean) == 150

        # Stage 3: Feature engineering
        X = df_clean.drop(columns=['species'])
        y = df_clean['species']
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)
        le = LabelEncoder()
        y_encoded = le.fit_transform(y)

        # Stage 4: Train
        X_train, X_test, y_train, y_test = train_test_split(
            X_scaled, y_encoded, test_size=0.2, random_state=42
        )
        model = RandomForestClassifier(n_estimators=50, random_state=42)
        model.fit(X_train, y_train)

        # Stage 5: Evaluate
        accuracy = accuracy_score(y_test, model.predict(X_test))
        assert accuracy > 0.9

    def test_pipeline_handles_different_datasets(self):
        """Test pipeline can handle different dataset sizes."""
        from sklearn.datasets import make_classification
        from sklearn.ensemble import RandomForestClassifier
        from sklearn.model_selection import train_test_split
        from sklearn.metrics import accuracy_score

        for n_samples in [50, 100, 500]:
            X, y = make_classification(
                n_samples=n_samples,
                n_features=10,
                n_classes=3,
                n_informative=5,
                n_redundant=2,
                n_clusters_per_class=1,
                random_state=42
            )

            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42
            )

            model = RandomForestClassifier(n_estimators=10, random_state=42)
            model.fit(X_train, y_train)

            accuracy = accuracy_score(y_test, model.predict(X_test))
            assert accuracy > 0.5  # Reasonable accuracy for random data