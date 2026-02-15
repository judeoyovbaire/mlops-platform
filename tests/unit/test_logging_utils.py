"""Unit tests for logging_utils module."""

import json
import logging

import pytest

from pipelines.training.src.logging_utils import (
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


class TestCorrelationId:
    """Tests for correlation ID functions."""

    def test_generate_correlation_id_format(self):
        """Test that generated IDs are valid UUIDs."""
        cid = generate_correlation_id()
        assert len(cid) == 36
        assert cid.count("-") == 4

    def test_generate_correlation_id_unique(self):
        """Test that each call generates a unique ID."""
        ids = {generate_correlation_id() for _ in range(100)}
        assert len(ids) == 100

    def test_set_and_get_correlation_id(self):
        """Test setting and retrieving correlation ID."""
        test_id = "test-correlation-id-123"
        set_correlation_id(test_id)
        assert get_correlation_id() == test_id

    def test_get_correlation_id_generates_if_empty(self):
        """Test that get_correlation_id generates ID if not set."""
        set_correlation_id("")
        cid = get_correlation_id()
        assert len(cid) == 36


class TestStructuredFormatter:
    """Tests for StructuredFormatter."""

    def test_format_produces_valid_json(self):
        """Test that formatter produces valid JSON."""
        formatter = StructuredFormatter(service_name="test-service")
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="test.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )

        output = formatter.format(record)
        data = json.loads(output)

        assert data["level"] == "INFO"
        assert data["message"] == "Test message"
        assert data["service"] == "test-service"
        assert "correlation_id" in data
        assert data["location"]["line"] == 42

    def test_format_includes_exception_info(self):
        """Test that exceptions are properly formatted."""
        formatter = StructuredFormatter()

        try:
            raise ValueError("Test error")
        except ValueError:
            import sys

            record = logging.LogRecord(
                name="test",
                level=logging.ERROR,
                pathname="test.py",
                lineno=1,
                msg="Error occurred",
                args=(),
                exc_info=sys.exc_info(),
            )

        output = formatter.format(record)
        data = json.loads(output)

        assert "exception" in data
        assert data["exception"]["type"] == "ValueError"
        assert "Test error" in data["exception"]["message"]


class TestHumanReadableFormatter:
    """Tests for HumanReadableFormatter."""

    def test_format_includes_short_correlation_id(self):
        """Test that format includes shortened correlation ID."""
        set_correlation_id("12345678-1234-1234-1234-123456789012")
        formatter = HumanReadableFormatter()
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="test.py",
            lineno=1,
            msg="Test message",
            args=(),
            exc_info=None,
        )

        output = formatter.format(record)

        assert "[12345678]" in output
        assert "INFO" in output
        assert "Test message" in output


class TestGetLogger:
    """Tests for get_logger function."""

    def test_returns_logger_adapter(self):
        """Test that get_logger returns a CorrelatedLoggerAdapter."""
        logger = get_logger("test.module")
        assert isinstance(logger, CorrelatedLoggerAdapter)

    def test_logger_has_correct_name(self):
        """Test that underlying logger has correct name."""
        logger = get_logger("my.test.logger")
        assert logger.logger.name == "my.test.logger"

    def test_logger_logs_with_extra_fields(self, capsys):
        """Test that extra fields are processed without errors."""
        logger = get_logger("test.extra.fields", structured=False)
        # Should not raise any exceptions
        logger.info("Test message", custom_field="value")

        captured = capsys.readouterr()
        assert "Test message" in captured.err


class TestStepLogging:
    """Tests for step logging helper functions."""

    def test_log_step_start(self, capsys):
        """Test log_step_start logs correct message."""
        logger = get_logger("test.step.start", structured=False)
        log_step_start(logger, "validate", input_file="data.csv")

        captured = capsys.readouterr()
        assert "Starting pipeline step: validate" in captured.err

    def test_log_step_complete(self, capsys):
        """Test log_step_complete logs correct message."""
        logger = get_logger("test.step.complete", structured=False)
        log_step_complete(logger, "train", duration_seconds=10.5)

        captured = capsys.readouterr()
        assert "Completed pipeline step: train" in captured.err

    def test_log_step_error(self, capsys):
        """Test log_step_error logs error correctly."""
        logger = get_logger("test.step.error", structured=False)
        log_step_error(logger, "feature_engineering", ValueError("Test error"))

        captured = capsys.readouterr()
        assert "Error in pipeline step feature_engineering" in captured.err
        assert "Test error" in captured.err
