"""Unit tests for load_data module."""

import io
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError

import pytest

from pipelines.training.src.exceptions import (
    DataLoadError,
    InvalidURLError,
    NetworkError,
)
from pipelines.training.src.load_data import LoadResult, load_data, validate_url


class TestValidateUrl:
    """Tests for URL validation."""

    def test_valid_https_url(self):
        """Test that valid HTTPS URLs pass validation."""
        assert validate_url("https://example.com/data.csv") is True

    def test_valid_http_url(self):
        """Test that valid HTTP URLs pass validation."""
        assert validate_url("http://example.com/data.csv") is True

    def test_invalid_scheme(self):
        """Test that unsupported schemes raise InvalidURLError."""
        with pytest.raises(InvalidURLError, match="Unsupported URL scheme"):
            validate_url("ftp://example.com/data.csv")

    def test_missing_scheme(self):
        """Test that URLs without scheme raise InvalidURLError."""
        with pytest.raises(InvalidURLError, match="Invalid URL format"):
            validate_url("example.com/data.csv")

    def test_empty_url(self):
        """Test that empty URLs raise InvalidURLError."""
        with pytest.raises(InvalidURLError, match="Invalid URL format"):
            validate_url("")


class TestLoadData:
    """Tests for load_data function."""

    def test_successful_download(self, temp_dir):
        """Test successful data download."""
        output_path = str(temp_dir / "output.csv")
        test_content = b"col1,col2\n1,2\n3,4\n"

        mock_response = MagicMock()
        mock_response.read.return_value = test_content
        mock_response.__enter__ = MagicMock(return_value=io.BytesIO(test_content))
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_response):
            result = load_data("https://example.com/data.csv", output_path)

            assert isinstance(result, LoadResult)
            assert result.success is True
            assert result.num_lines == 3
            assert result.output_path == output_path

    def test_http_error(self, temp_dir):
        """Test handling of HTTP errors."""
        output_path = str(temp_dir / "output.csv")

        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_urlopen.side_effect = HTTPError("https://example.com", 404, "Not Found", {}, None)

            with pytest.raises(NetworkError, match="HTTP error"):
                load_data("https://example.com/data.csv", output_path)

    def test_url_error(self, temp_dir):
        """Test handling of URL/network errors."""
        output_path = str(temp_dir / "output.csv")

        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_urlopen.side_effect = URLError("Connection refused")

            with pytest.raises(NetworkError, match="URL error"):
                load_data("https://example.com/data.csv", output_path)

    def test_invalid_url_format(self, temp_dir):
        """Test that invalid URLs are rejected."""
        output_path = str(temp_dir / "output.csv")

        with pytest.raises(InvalidURLError, match="Invalid URL format"):
            load_data("not-a-url", output_path)

    def test_empty_file_download(self, temp_dir):
        """Test handling of empty downloaded files."""
        output_path = str(temp_dir / "output.csv")
        test_content = b"header\n"  # Only header, no data

        mock_response = MagicMock()
        mock_response.__enter__ = MagicMock(return_value=io.BytesIO(test_content))
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_response):
            with pytest.raises(DataLoadError, match="empty"):
                load_data("https://example.com/data.csv", output_path)

    def test_file_not_created(self, temp_dir):
        """Test handling when file cannot be written (OSError)."""
        # Use an invalid path that will cause an OSError
        output_path = "/nonexistent/directory/output.csv"

        mock_response = MagicMock()
        mock_response.__enter__ = MagicMock(return_value=io.BytesIO(b"test\n"))
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_response):
            with pytest.raises(DataLoadError, match="File system error"):
                load_data("https://example.com/data.csv", output_path)

    def test_result_dataclass_fields(self, temp_dir):
        """Test that LoadResult contains expected fields."""
        output_path = str(temp_dir / "output.csv")
        test_content = b"col1,col2\n1,2\n3,4\n5,6\n"

        mock_response = MagicMock()
        mock_response.__enter__ = MagicMock(return_value=io.BytesIO(test_content))
        mock_response.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_response):
            result = load_data("https://example.com/data.csv", output_path)

            assert hasattr(result, "output_path")
            assert hasattr(result, "num_lines")
            assert hasattr(result, "success")
            assert hasattr(result, "error_message")
