"""Feast feature definitions for the MLOps Platform."""

from datetime import timedelta

from feast import Entity, FeatureView, Field, FileSource
from feast.types import Float32, String

# Entity: an individual iris sample identified by its row index
iris_sample = Entity(
    name="iris_sample_id",
    join_keys=["sample_id"],
    description="Unique identifier for an iris sample",
)

# Offline source: parquet file produced by the feature-engineering step
iris_source = FileSource(
    path="data/iris_features.parquet",
    timestamp_field="event_timestamp",
)

# Feature view: engineered iris features
iris_feature_view = FeatureView(
    name="iris_features",
    entities=[iris_sample],
    ttl=timedelta(days=7),
    schema=[
        Field(name="sepal_length", dtype=Float32),
        Field(name="sepal_width", dtype=Float32),
        Field(name="petal_length", dtype=Float32),
        Field(name="petal_width", dtype=Float32),
        Field(name="species", dtype=String),
    ],
    source=iris_source,
    online=True,
    description="Engineered iris features for classification",
)
