"""Unit tests for Feast feature store definitions.

These tests require feast to be installed (pip install feast).
Skip with: pytest -k "not feature_store" if feast is not available.
"""

import pytest

feast = pytest.importorskip("feast", reason="feast is not installed")

import sys  # noqa: E402
from pathlib import Path  # noqa: E402

_feature_store_dir = str(Path(__file__).resolve().parents[2] / "pipelines" / "feature-store")
if _feature_store_dir not in sys.path:
    sys.path.insert(0, _feature_store_dir)

from features import iris_feature_view, iris_sample, iris_source  # noqa: E402


class TestIrisEntity:
    """Tests for iris entity definition."""

    def test_entity_name(self):
        assert iris_sample.name == "iris_sample_id"

    def test_entity_join_keys(self):
        assert iris_sample.join_keys == ["sample_id"]

    def test_entity_description(self):
        assert iris_sample.description == "Unique identifier for an iris sample"


class TestIrisFeatureView:
    """Tests for iris feature view definition."""

    def test_feature_view_name(self):
        assert iris_feature_view.name == "iris_features"

    def test_feature_view_schema_fields(self):
        schema_field_names = [field.name for field in iris_feature_view.schema]
        for field_name in ["sepal_length", "sepal_width", "petal_length", "petal_width", "species"]:
            assert field_name in schema_field_names

    def test_feature_view_online_enabled(self):
        assert iris_feature_view.online is True

    def test_feature_view_source(self):
        assert iris_feature_view.batch_source is iris_source

    def test_feature_view_entities(self):
        entity_names = [e.name for e in iris_feature_view.entities]
        assert "iris_sample_id" in entity_names

    def test_feature_view_schema_types(self):
        from feast.types import Float32, String

        field_types = {field.name: field.dtype for field in iris_feature_view.schema}
        for col in ["sepal_length", "sepal_width", "petal_length", "petal_width"]:
            assert field_types[col] == Float32
        assert field_types["species"] == String
