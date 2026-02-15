"""
Pandera schemas for pipeline data validation.

Defines column-level expectations (types, ranges, allowed values) that are
checked **before** the rest of the validation / cleaning pipeline runs.
This catches upstream data-quality issues early rather than having them
surface as cryptic sklearn or pandas errors downstream.
"""

import pandera.pandas as pa

# ---------------------------------------------------------------------------
# Iris training-data schema
# ---------------------------------------------------------------------------
# The schema is intentionally lenient on nullability — the downstream
# validate_data step handles imputation.  The purpose here is to enforce
# *structural* correctness (column names, dtypes, value ranges).

IrisSchema = pa.DataFrameSchema(
    columns={
        "sepal_length": pa.Column(
            float,
            checks=[
                pa.Check.ge(0, error="sepal_length must be non-negative"),
                pa.Check.le(15, error="sepal_length unreasonably large (> 15 cm)"),
            ],
            nullable=True,
            description="Sepal length in cm",
        ),
        "sepal_width": pa.Column(
            float,
            checks=[
                pa.Check.ge(0, error="sepal_width must be non-negative"),
                pa.Check.le(10, error="sepal_width unreasonably large (> 10 cm)"),
            ],
            nullable=True,
            description="Sepal width in cm",
        ),
        "petal_length": pa.Column(
            float,
            checks=[
                pa.Check.ge(0, error="petal_length must be non-negative"),
                pa.Check.le(15, error="petal_length unreasonably large (> 15 cm)"),
            ],
            nullable=True,
            description="Petal length in cm",
        ),
        "petal_width": pa.Column(
            float,
            checks=[
                pa.Check.ge(0, error="petal_width must be non-negative"),
                pa.Check.le(10, error="petal_width unreasonably large (> 10 cm)"),
            ],
            nullable=True,
            description="Petal width in cm",
        ),
        "species": pa.Column(
            str,
            checks=pa.Check.isin(
                ["setosa", "versicolor", "virginica"],
                error="species must be one of: setosa, versicolor, virginica",
            ),
            nullable=True,
            description="Iris species label",
        ),
    },
    strict=False,  # allow extra columns (e.g. engineered features)
    coerce=True,  # coerce types before checking
)
