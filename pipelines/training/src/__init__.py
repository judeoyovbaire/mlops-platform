"""
ML Training Pipeline Source Module.

This module exports all pipeline step functions for easy importing.
"""

try:
    from pipelines.training.src.exceptions import (
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
    from pipelines.training.src.feature_engineering import feature_engineering
    from pipelines.training.src.load_data import load_data
    from pipelines.training.src.logging_utils import (
        generate_correlation_id,
        get_correlation_id,
        get_logger,
        log_step_complete,
        log_step_error,
        log_step_start,
        set_correlation_id,
    )
    from pipelines.training.src.mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout
    from pipelines.training.src.register_model import register_model
    from pipelines.training.src.train_model import train_model
    from pipelines.training.src.validate_data import validate_data
except ImportError:
    from exceptions import (  # type: ignore[no-redef]
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
    from feature_engineering import feature_engineering  # type: ignore[no-redef]
    from load_data import load_data  # type: ignore[no-redef]
    from logging_utils import (  # type: ignore[no-redef]
        generate_correlation_id,
        get_correlation_id,
        get_logger,
        log_step_complete,
        log_step_error,
        log_step_start,
        set_correlation_id,
    )
    from mlflow_utils import MLFLOW_CONNECTION_TIMEOUT, run_with_timeout  # type: ignore[no-redef]
    from register_model import register_model  # type: ignore[no-redef]
    from train_model import train_model  # type: ignore[no-redef]
    from validate_data import validate_data  # type: ignore[no-redef]

__all__ = [
    # Functions
    "load_data",
    "validate_data",
    "feature_engineering",
    "train_model",
    "register_model",
    # MLflow utilities
    "run_with_timeout",
    "MLFLOW_CONNECTION_TIMEOUT",
    # Logging utilities
    "get_logger",
    "get_correlation_id",
    "set_correlation_id",
    "generate_correlation_id",
    "log_step_start",
    "log_step_complete",
    "log_step_error",
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
