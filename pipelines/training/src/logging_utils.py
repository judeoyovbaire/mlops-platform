"""
Structured logging utilities for ML pipeline.

This module provides consistent, structured logging with correlation ID
support for tracing requests across pipeline steps.
"""

import json
import logging
import os
import uuid
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any

# Context variable for correlation ID - thread-safe and async-safe
_correlation_id: ContextVar[str] = ContextVar("correlation_id", default="")


def generate_correlation_id() -> str:
    """Generate a new correlation ID."""
    return str(uuid.uuid4())


def get_correlation_id() -> str:
    """Get the current correlation ID, generating one if not set."""
    cid = _correlation_id.get()
    if not cid:
        cid = generate_correlation_id()
        _correlation_id.set(cid)
    return cid


def set_correlation_id(correlation_id: str) -> None:
    """Set the correlation ID for the current context."""
    _correlation_id.set(correlation_id)


class StructuredFormatter(logging.Formatter):
    """
    JSON formatter for structured logging.

    Outputs log records as JSON objects with consistent fields for
    easy parsing by log aggregation systems (ELK, Loki, etc.).
    """

    def __init__(self, service_name: str = "ml-pipeline"):
        super().__init__()
        self.service_name = service_name

    def format(self, record: logging.LogRecord) -> str:
        """Format the log record as a JSON string."""
        log_data: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": self.service_name,
            "correlation_id": get_correlation_id(),
        }

        # Add location info
        log_data["location"] = {
            "file": record.filename,
            "line": record.lineno,
            "function": record.funcName,
        }

        # Add thread info for debugging concurrency issues
        log_data["thread"] = {
            "id": record.thread,
            "name": record.threadName,
        }

        # Add extra fields if present
        if hasattr(record, "extra_fields"):
            log_data["extra"] = record.extra_fields

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = {
                "type": record.exc_info[0].__name__ if record.exc_info[0] else None,
                "message": str(record.exc_info[1]) if record.exc_info[1] else None,
                "traceback": self.formatException(record.exc_info),
            }

        return json.dumps(log_data, default=str)


class HumanReadableFormatter(logging.Formatter):
    """
    Human-readable formatter that includes correlation ID.

    Used for local development and debugging.
    """

    def format(self, record: logging.LogRecord) -> str:
        """Format the log record with correlation ID prefix."""
        correlation_id = get_correlation_id()
        short_id = correlation_id[:8] if correlation_id else "--------"

        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        base = f"{timestamp} [{short_id}] {record.levelname:8} {record.name}: {record.getMessage()}"

        if record.exc_info:
            base += f"\n{self.formatException(record.exc_info)}"

        return base


class CorrelatedLoggerAdapter(logging.LoggerAdapter):
    """
    Logger adapter that automatically includes extra context fields.

    Usage:
        logger = get_logger(__name__)
        logger.info("Processing started", input_file="data.csv", rows=1000)
    """

    def process(
        self, msg: str, kwargs: dict[str, Any]
    ) -> tuple[str, dict[str, Any]]:
        """Process the logging call to add extra fields."""
        # Extract extra fields from kwargs
        extra_fields = {}
        standard_keys = {"exc_info", "stack_info", "stacklevel", "extra"}

        for key in list(kwargs.keys()):
            if key not in standard_keys:
                extra_fields[key] = kwargs.pop(key)

        # Add extra fields to the record
        if extra_fields:
            kwargs.setdefault("extra", {})
            kwargs["extra"]["extra_fields"] = extra_fields

        return msg, kwargs


def get_logger(
    name: str,
    level: int | None = None,
    structured: bool | None = None,
) -> CorrelatedLoggerAdapter:
    """
    Get a logger configured for the ML pipeline.

    Args:
        name: Logger name, typically __name__.
        level: Logging level (default: from LOG_LEVEL env var or INFO).
        structured: If True, use JSON format. If False, use human-readable.
                   Default: from STRUCTURED_LOGGING env var.

    Returns:
        A logger adapter with correlation ID support.

    Example:
        logger = get_logger(__name__)
        logger.info("Starting processing", step="validate", rows=100)
    """
    logger = logging.getLogger(name)

    # Determine level from env var or default
    if level is None:
        level_name = os.environ.get("LOG_LEVEL", "INFO").upper()
        level = getattr(logging, level_name, logging.INFO)

    logger.setLevel(level)

    # Only add handler if logger has no handlers
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setLevel(level)

        # Determine format from env var or parameter
        if structured is None:
            structured = os.environ.get("STRUCTURED_LOGGING", "false").lower() == "true"

        if structured:
            service_name = os.environ.get("SERVICE_NAME", "ml-pipeline")
            handler.setFormatter(StructuredFormatter(service_name=service_name))
        else:
            handler.setFormatter(HumanReadableFormatter())

        logger.addHandler(handler)

        # Prevent propagation to root logger to avoid duplicate logs
        logger.propagate = False

    return CorrelatedLoggerAdapter(logger, {})


def log_step_start(logger: CorrelatedLoggerAdapter, step_name: str, **kwargs: Any) -> None:
    """Log the start of a pipeline step with context."""
    logger.info(
        f"Starting pipeline step: {step_name}",
        step=step_name,
        event="step_start",
        **kwargs,
    )


def log_step_complete(
    logger: CorrelatedLoggerAdapter,
    step_name: str,
    duration_seconds: float | None = None,
    **kwargs: Any,
) -> None:
    """Log the completion of a pipeline step."""
    logger.info(
        f"Completed pipeline step: {step_name}",
        step=step_name,
        event="step_complete",
        duration_seconds=duration_seconds,
        **kwargs,
    )


def log_step_error(
    logger: CorrelatedLoggerAdapter,
    step_name: str,
    error: Exception,
    **kwargs: Any,
) -> None:
    """Log an error during a pipeline step."""
    logger.error(
        f"Error in pipeline step {step_name}: {error}",
        step=step_name,
        event="step_error",
        error_type=type(error).__name__,
        error_message=str(error),
        exc_info=True,
        **kwargs,
    )
