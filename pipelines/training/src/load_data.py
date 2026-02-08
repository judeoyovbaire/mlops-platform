"""
Load data from URL for ML pipeline.

This module downloads data from a specified URL and saves it locally.
It includes validation for URL format and proper error handling for
network issues.
"""

import argparse
import os
import shutil
import sys
import urllib.request
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse

from pipelines.training.src.exceptions import DataLoadError, InvalidURLError, NetworkError
from pipelines.training.src.logging_utils import get_logger

logger = get_logger(__name__)

# Default timeout for network requests (seconds)
DEFAULT_TIMEOUT = 30

# Encodings to try in order of preference
ENCODING_FALLBACKS = ["utf-8", "latin-1", "cp1252", "iso-8859-1"]


@dataclass
class LoadResult:
    """Result of data loading operation."""

    output_path: str
    num_lines: int
    detected_encoding: str
    success: bool
    error_message: str | None = None


def detect_encoding(file_path: str) -> str:
    """
    Detect the encoding of a file by trying multiple encodings.

    Args:
        file_path: Path to the file to check.

    Returns:
        The detected encoding name.

    Raises:
        DataLoadError: If no valid encoding is found.
    """
    for encoding in ENCODING_FALLBACKS:
        try:
            with open(file_path, encoding=encoding) as f:
                f.read()
            logger.info(f"Detected encoding: {encoding}")
            return encoding
        except UnicodeDecodeError:
            continue

    raise DataLoadError(
        f"Unable to decode file with any of the following encodings: {ENCODING_FALLBACKS}"
    )


def validate_url(url: str) -> bool:
    """
    Validate that the URL is well-formed and uses a supported scheme.

    Args:
        url: The URL to validate.

    Returns:
        True if the URL is valid.

    Raises:
        InvalidURLError: If the URL is malformed or uses an unsupported scheme.
    """
    try:
        result = urlparse(url)
        if not all([result.scheme, result.netloc]):
            raise InvalidURLError(f"Invalid URL format: {url}")
        if result.scheme not in ("http", "https"):
            raise InvalidURLError(f"Unsupported URL scheme: {result.scheme}")
        return True
    except ValueError as e:
        raise InvalidURLError(f"Failed to parse URL: {e}") from e


def load_data(url: str, output_path: str, timeout: int = DEFAULT_TIMEOUT) -> LoadResult:
    """
    Download data from a URL and save it to the specified path.

    Args:
        url: URL to download data from.
        output_path: Local path to save the downloaded data.
        timeout: Network timeout in seconds (default: 30).

    Returns:
        LoadResult containing the output path, number of lines, and status.

    Raises:
        InvalidURLError: If the URL is malformed.
        NetworkError: If the download fails due to network issues.
        DataLoadError: If the downloaded file is empty or invalid.
    """
    logger.info(f"Starting data load from {url}")

    # Validate timeout range
    if timeout < 1 or timeout > 300:
        raise DataLoadError(f"Timeout must be between 1 and 300 seconds, got: {timeout}")

    # Validate URL format
    validate_url(url)

    try:
        logger.info(f"Downloading data from {url} (timeout: {timeout}s)")
        with urllib.request.urlopen(url, timeout=timeout) as response:
            with open(output_path, "wb") as out_file:
                shutil.copyfileobj(response, out_file)

        # Verify download
        if not os.path.exists(output_path):
            raise DataLoadError(f"Output file {output_path} not found after download")

        # Detect encoding with fallback
        detected_encoding = detect_encoding(output_path)

        with open(output_path, encoding=detected_encoding) as f:
            lines = f.readlines()
            num_lines = len(lines)
            logger.info(f"Downloaded {num_lines} lines (encoding: {detected_encoding})")

            if num_lines < 2:
                raise DataLoadError("Downloaded file appears empty (less than 2 lines)")

        logger.info(f"Data successfully saved to {output_path}")
        return LoadResult(
            output_path=output_path,
            num_lines=num_lines,
            detected_encoding=detected_encoding,
            success=True,
        )

    except HTTPError as e:
        error_msg = f"HTTP error downloading data: {e.code} {e.reason}"
        logger.error(error_msg)
        raise NetworkError(error_msg) from e

    except URLError as e:
        error_msg = f"URL error downloading data: {e.reason}"
        logger.error(error_msg)
        raise NetworkError(error_msg) from e

    except OSError as e:
        error_msg = f"File system error: {e}"
        logger.error(error_msg)
        raise DataLoadError(error_msg) from e


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Load data from URL")
    parser.add_argument("--url", required=True, help="URL to download data from")
    parser.add_argument("--output", required=True, help="Path to save the data")

    args = parser.parse_args()

    # Ensure directory exists
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    try:
        result = load_data(args.url, args.output)
        print(
            f"Downloaded {result.num_lines} lines to {result.output_path} "
            f"(encoding: {result.detected_encoding})"
        )
    except (InvalidURLError, NetworkError, DataLoadError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
