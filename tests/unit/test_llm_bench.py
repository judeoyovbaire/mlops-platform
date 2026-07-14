"""Unit tests for the LLM benchmark harness stats (scripts/benchmark)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "benchmark"))

from llm_bench import RequestResult, aggregate, cost_per_mtok, percentile, to_markdown


class TestPercentile:
    def test_empty_is_zero(self):
        assert percentile([], 95) == 0.0

    def test_single_value(self):
        assert percentile([2.5], 50) == 2.5
        assert percentile([2.5], 95) == 2.5

    def test_p50_and_p95_ordering(self):
        values = [float(i) for i in range(1, 101)]
        assert percentile(values, 50) <= percentile(values, 95)
        assert percentile(values, 95) >= 90.0


class TestAggregate:
    def test_errors_counted_and_excluded_from_stats(self):
        results = [
            RequestResult(ttft_s=0.1, total_s=1.0, output_tokens=100, ok=True),
            RequestResult(ttft_s=0.0, total_s=5.0, output_tokens=0, ok=False, error="boom"),
        ]
        agg = aggregate(results, wall_s=5.0)
        assert agg["ok"] == 1
        assert agg["errors"] == 1
        assert agg["total_output_tokens"] == 100
        assert agg["aggregate_tokens_per_s"] == 20.0

    def test_zero_wall_clock_is_safe(self):
        agg = aggregate([], wall_s=0.0)
        assert agg["aggregate_tokens_per_s"] == 0.0


class TestCostPerMtok:
    def test_basic_math(self):
        # 1000 tok/s = 3.6M tok/hr; at $0.72/hr -> $0.20/Mtok
        assert cost_per_mtok(1000.0, 0.72) == 0.2

    def test_zero_throughput_is_safe(self):
        assert cost_per_mtok(0.0, 0.77) == 0.0


class TestMarkdown:
    def test_report_renders_all_levels(self):
        run = {
            "model": "qwen25-7b",
            "base_url": "http://localhost:8080",
            "max_tokens": 256,
            "requests_per_level": 24,
            "gpu": "g5.xlarge (A10G 24GB)",
            "gpu_hourly_usd": 0.77,
            "date": "2026-07-14",
            "levels": [
                {
                    "concurrency": 1,
                    "ok": 24,
                    "errors": 0,
                    "ttft_p50_s": 0.09,
                    "ttft_p95_s": 0.15,
                    "latency_p50_s": 3.1,
                    "latency_p95_s": 3.4,
                    "per_request_tokens_per_s_median": 82.0,
                    "aggregate_tokens_per_s": 80.5,
                    "cost_per_mtok_usd": 2.657,
                }
            ],
        }
        md = to_markdown(run)
        assert "qwen25-7b" in md
        assert "| 1 | 24/0 |" in md
        assert "$/Mtok" in md
