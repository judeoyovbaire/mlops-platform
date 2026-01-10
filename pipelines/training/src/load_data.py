import argparse
import os
import sys
import urllib.request


def load_data(url, output_path):
    try:
        print(f"Downloading data from {url}")
        urllib.request.urlretrieve(url, output_path)

        # Verify download
        if not os.path.exists(output_path):
            print(f"Error: Output file {output_path} not found", file=sys.stderr)
            sys.exit(1)

        with open(output_path) as f:
            lines = f.readlines()
            print(f"Downloaded {len(lines)} lines")
            if len(lines) < 2:
                print("Error: Downloaded file appears empty", file=sys.stderr)
                sys.exit(1)

    except Exception as e:
        print(f"Error downloading data: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Load data from URL")
    parser.add_argument("--url", required=True, help="URL to download data from")
    parser.add_argument("--output", required=True, help="Path to save the data")

    args = parser.parse_args()

    # Ensure directory exists
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    load_data(args.url, args.output)
