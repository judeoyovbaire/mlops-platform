# Feature Store (Feast)

Minimal Feast feature store configuration for the MLOps Platform.

## Setup

```bash
pip install feast
cd pipelines/feature-store
feast apply
```

## Usage

```python
from feast import FeatureStore

store = FeatureStore(repo_path="pipelines/feature-store")

# Get training features (offline)
training_df = store.get_historical_features(
    entity_df=entity_df,
    features=["iris_features:sepal_length", "iris_features:petal_width"],
).to_df()

# Get online features (for inference)
features = store.get_online_features(
    features=["iris_features:sepal_length", "iris_features:petal_width"],
    entity_rows=[{"sample_id": 1}],
).to_dict()
```

## Architecture

- **Provider**: Local (SQLite) -- suitable for development and testing
- **Online Store**: SQLite database for low-latency feature serving
- **Offline Store**: File-based (Parquet) for training data retrieval
- **Production**: Replace with Redis (online) and BigQuery/Redshift (offline)
