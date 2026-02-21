"""
Shared utilities for ML pipeline components.

This package contains modules that are used across both the training
and pretrained pipelines: structured logging, custom exceptions,
and MLflow helper functions.
"""

from pipelines.shared.exceptions import (
    DataLoadError,
    DataValidationError,
    EmptyDataError,
    FeatureEngineeringError,
    InsufficientDataError,
    InvalidThresholdError,
    InvalidURLError,
    MissingColumnError,
    MLflowTimeoutError,
    ModelRegistrationError,
    ModelTrainingError,
    NetworkError,
    PipelineError,
)
from pipelines.shared.logging_utils import (
    CorrelatedLoggerAdapter,
    HumanReadableFormatter,
    StructuredFormatter,
    generate_correlation_id,
    get_correlation_id,
    get_logger,
    log_step_complete,
    log_step_error,
    log_step_start,
    set_correlation_id,
)
from pipelines.shared.mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout

__all__ = [
    # Logging utilities
    "get_logger",
    "get_correlation_id",
    "set_correlation_id",
    "generate_correlation_id",
    "log_step_start",
    "log_step_complete",
    "log_step_error",
    "CorrelatedLoggerAdapter",
    "StructuredFormatter",
    "HumanReadableFormatter",
    # MLflow utilities
    "run_with_timeout",
    "MLFLOW_CONNECTION_TIMEOUT",
    # Exceptions
    "PipelineError",
    "DataLoadError",
    "DataValidationError",
    "FeatureEngineeringError",
    "ModelTrainingError",
    "ModelRegistrationError",
    "InsufficientDataError",
    "MissingColumnError",
    "InvalidURLError",
    "NetworkError",
    "EmptyDataError",
    "InvalidThresholdError",
    "MLflowTimeoutError",
]
