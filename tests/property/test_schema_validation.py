"""Property-based tests for Pandera schema validation.

Uses Hypothesis to verify:
- Valid data always passes schema validation
- Invalid data (negative values, wrong species) always fails
"""

import numpy as np
import pandas as pd
import pandera
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from pipelines.training.src.schema import IrisSchema

# Strategy: generate valid iris-like DataFrames
valid_species = st.sampled_from(["setosa", "versicolor", "virginica"])


@given(
    sepal_length=st.floats(min_value=0.1, max_value=14.9),
    sepal_width=st.floats(min_value=0.1, max_value=9.9),
    petal_length=st.floats(min_value=0.1, max_value=14.9),
    petal_width=st.floats(min_value=0.1, max_value=9.9),
    species=valid_species,
)
@settings(max_examples=50, deadline=5000)
def test_valid_data_always_passes(sepal_length, sepal_width, petal_length, petal_width, species):
    """Any DataFrame with values in valid ranges must pass schema validation."""
    df = pd.DataFrame(
        {
            "sepal_length": [sepal_length],
            "sepal_width": [sepal_width],
            "petal_length": [petal_length],
            "petal_width": [petal_width],
            "species": [species],
        }
    )

    validated = IrisSchema.validate(df)
    assert len(validated) == 1


@given(
    negative_val=st.floats(min_value=-1000, max_value=-0.01),
    good_val=st.floats(min_value=0.1, max_value=5.0),
    species=valid_species,
)
@settings(max_examples=30, deadline=5000)
def test_negative_values_always_rejected(negative_val, good_val, species):
    """Any DataFrame with negative measurements must fail schema validation."""
    df = pd.DataFrame(
        {
            "sepal_length": [negative_val],
            "sepal_width": [good_val],
            "petal_length": [good_val],
            "petal_width": [good_val],
            "species": [species],
        }
    )

    with pytest.raises(pandera.errors.SchemaError):
        IrisSchema.validate(df)


@given(
    bad_species=st.text(min_size=1, max_size=20).filter(
        lambda s: s not in ["setosa", "versicolor", "virginica"]
    ),
    val=st.floats(min_value=0.1, max_value=5.0),
)
@settings(max_examples=30, deadline=5000)
def test_invalid_species_always_rejected(bad_species, val):
    """Any DataFrame with an invalid species name must fail schema validation."""
    df = pd.DataFrame(
        {
            "sepal_length": [val],
            "sepal_width": [val],
            "petal_length": [val],
            "petal_width": [val],
            "species": [bad_species],
        }
    )

    with pytest.raises(pandera.errors.SchemaError):
        IrisSchema.validate(df)


@given(
    huge_val=st.floats(min_value=16, max_value=1000),
    good_val=st.floats(min_value=0.1, max_value=5.0),
    species=valid_species,
)
@settings(max_examples=30, deadline=5000)
def test_unreasonably_large_values_rejected(huge_val, good_val, species):
    """Values exceeding the schema's upper bound must fail validation."""
    df = pd.DataFrame(
        {
            "sepal_length": [huge_val],
            "sepal_width": [good_val],
            "petal_length": [good_val],
            "petal_width": [good_val],
            "species": [species],
        }
    )

    with pytest.raises(pandera.errors.SchemaError):
        IrisSchema.validate(df)


@given(
    n_rows=st.integers(min_value=1, max_value=50),
)
@settings(max_examples=20, deadline=5000)
def test_valid_batch_always_passes(n_rows):
    """Batches of valid rows must always pass validation regardless of size."""
    rng = np.random.default_rng(42)
    df = pd.DataFrame(
        {
            "sepal_length": rng.uniform(0.1, 14.9, n_rows),
            "sepal_width": rng.uniform(0.1, 9.9, n_rows),
            "petal_length": rng.uniform(0.1, 14.9, n_rows),
            "petal_width": rng.uniform(0.1, 9.9, n_rows),
            "species": rng.choice(["setosa", "versicolor", "virginica"], n_rows),
        }
    )

    validated = IrisSchema.validate(df)
    assert len(validated) == n_rows
