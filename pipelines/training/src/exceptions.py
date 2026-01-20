"""
Custom exceptions for ML pipeline components.

This module defines a hierarchy of exceptions for handling errors
across the ML training pipeline stages.
"""


class PipelineError(Exception):
    """Base exception for all pipeline errors."""

    pass


class DataLoadError(PipelineError):
    """Raised when data loading fails."""

    pass


class DataValidationError(PipelineError):
    """Raised when data validation fails."""

    pass


class FeatureEngineeringError(PipelineError):
    """Raised when feature engineering fails."""

    pass


class ModelTrainingError(PipelineError):
    """Raised when model training fails."""

    pass


class ModelRegistrationError(PipelineError):
    """Raised when model registration fails."""

    pass


class InsufficientDataError(DataValidationError):
    """Raised when there is not enough data to proceed."""

    pass


class MissingColumnError(DataValidationError):
    """Raised when a required column is missing from the data."""

    pass


class InvalidURLError(DataLoadError):
    """Raised when a URL is invalid or malformed."""

    pass


class NetworkError(DataLoadError):
    """Raised when a network request fails."""

    pass


class EmptyDataError(DataValidationError):
    """Raised when the dataset is empty after processing."""

    pass


class InvalidThresholdError(ModelRegistrationError):
    """Raised when a threshold value is invalid."""

    pass
