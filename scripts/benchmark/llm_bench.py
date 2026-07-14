"""LLM serving benchmark against an OpenAI-compatible endpoint (JDH-376).

Measures what actually matters for serving economics, per configuration
and concurrency level:

- TTFT (time to first token) p50/p95 - the interactivity number
- End-to-end request latency p50/p95
- Output tokens/second per request (decode speed)
- Aggregate throughput (total output tokens/s across the run) - the
  continuous-batching payoff and the denominator of $/Mtok

Stdlib only (urllib + threads): runs anywhere, no dependencies to drift.
Results are written as JSON (machine) and Markdown (repo evidence).

Usage:
  kubectl port-forward -n mlops svc/<predictor-svc> 8080:80 &
  python llm_bench.py --base-url http://localhost:8080 --model qwen25-7b \
      --concurrency 1,4,8,16 --requests-per-level 24 \
      --output-json results-bf16.json --output-md results-bf16.md \
      --gpu-hourly-usd 0.77
"""

import argparse
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

PROMPTS = [
    "Explain the difference between a Deployment and a StatefulSet in Kubernetes.",
    "Summarize the tradeoffs between spot and on-demand cloud instances.",
    "Write a short function in Python that parses ISO-8601 timestamps.",
    "What is continuous batching in LLM inference and why does it matter?",
    "Describe how a model registry fits into an MLOps platform.",
    "Explain what a service mesh does, in three sentences.",
    "What are the failure modes of distributed consensus systems?",
    "Compare quantization approaches AWQ and GPTQ briefly.",
]


@dataclass
class RequestResult:
    ttft_s: float
    total_s: float
    output_tokens: int
    ok: bool
    error: str | None = None


def one_request(base_url: str, model: str, prompt: str, max_tokens: int) -> RequestResult:
    """Streamed chat completion; TTFT = first SSE data chunk with content."""
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0.0,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
    ).encode()
    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    start = time.monotonic()
    ttft = None
    output_tokens = 0
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            for raw in resp:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                chunk = json.loads(payload)
                if chunk.get("usage"):
                    output_tokens = chunk["usage"].get("completion_tokens", output_tokens)
                choices = chunk.get("choices") or []
                if ttft is None and choices and choices[0].get("delta", {}).get("content"):
                    ttft = time.monotonic() - start
        total = time.monotonic() - start
        return RequestResult(
            ttft_s=ttft or total, total_s=total, output_tokens=output_tokens, ok=True
        )
    except Exception as e:  # noqa: BLE001 - benchmark records, never crashes
        return RequestResult(
            ttft_s=0.0, total_s=time.monotonic() - start, output_tokens=0, ok=False, error=str(e)
        )


def percentile(values: list[float], pct: float) -> float:
    """Nearest-rank percentile; safe on small samples."""
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(0, min(len(ordered) - 1, round(pct / 100 * (len(ordered) - 1))))
    return ordered[rank]


def aggregate(results: list[RequestResult], wall_s: float) -> dict:
    """Reduce one concurrency level's results to the reported metrics."""
    ok = [r for r in results if r.ok]
    ttfts = [r.ttft_s for r in ok]
    totals = [r.total_s for r in ok]
    decode_rates = [r.output_tokens / r.total_s for r in ok if r.total_s > 0 and r.output_tokens]
    total_tokens = sum(r.output_tokens for r in ok)
    return {
        "requests": len(results),
        "ok": len(ok),
        "errors": len(results) - len(ok),
        "ttft_p50_s": round(percentile(ttfts, 50), 3),
        "ttft_p95_s": round(percentile(ttfts, 95), 3),
        "latency_p50_s": round(percentile(totals, 50), 3),
        "latency_p95_s": round(percentile(totals, 95), 3),
        "per_request_tokens_per_s_median": round(percentile(decode_rates, 50), 1),
        "aggregate_tokens_per_s": round(total_tokens / wall_s, 1) if wall_s > 0 else 0.0,
        "total_output_tokens": total_tokens,
        "wall_clock_s": round(wall_s, 1),
    }


def cost_per_mtok(aggregate_tokens_per_s: float, gpu_hourly_usd: float) -> float:
    """USD per million output tokens at this throughput on this GPU."""
    if aggregate_tokens_per_s <= 0:
        return 0.0
    tokens_per_hour = aggregate_tokens_per_s * 3600
    return round(gpu_hourly_usd / (tokens_per_hour / 1_000_000), 3)


def run_level(
    base_url: str, model: str, concurrency: int, n_requests: int, max_tokens: int
) -> dict:
    prompts = [PROMPTS[i % len(PROMPTS)] for i in range(n_requests)]
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        results = list(pool.map(lambda p: one_request(base_url, model, p, max_tokens), prompts))
    wall = time.monotonic() - start
    level = aggregate(results, wall)
    level["concurrency"] = concurrency
    errors = [r.error for r in results if r.error]
    if errors:
        level["first_error"] = errors[0][:200]
    return level


def to_markdown(run: dict) -> str:
    lines = [
        f"# LLM benchmark: {run['model']}",
        "",
        f"- endpoint: `{run['base_url']}`  ",
        f"- max_tokens: {run['max_tokens']}, requests/level: {run['requests_per_level']}  ",
        f"- GPU: {run['gpu']} @ ${run['gpu_hourly_usd']}/hr (spot)  ",
        f"- date: {run['date']}",
        "",
        "| conc | ok/err | TTFT p50 | TTFT p95 | e2e p50 | e2e p95 | tok/s per-req | tok/s aggregate | $/Mtok |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for lv in run["levels"]:
        lines.append(
            f"| {lv['concurrency']} | {lv['ok']}/{lv['errors']} "
            f"| {lv['ttft_p50_s']}s | {lv['ttft_p95_s']}s "
            f"| {lv['latency_p50_s']}s | {lv['latency_p95_s']}s "
            f"| {lv['per_request_tokens_per_s_median']} "
            f"| {lv['aggregate_tokens_per_s']} "
            f"| {lv['cost_per_mtok_usd']} |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", required=True, help="served-model-name of the endpoint")
    parser.add_argument("--concurrency", default="1,4,8,16")
    parser.add_argument("--requests-per-level", type=int, default=24)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--gpu", default="g5.xlarge (A10G 24GB)")
    parser.add_argument("--gpu-hourly-usd", type=float, default=0.77)
    parser.add_argument("--output-json", default=None)
    parser.add_argument("--output-md", default=None)
    parser.add_argument("--date", default=None, help="ISO date stamp for the report")
    args = parser.parse_args()

    levels = []
    for c in [int(x) for x in args.concurrency.split(",")]:
        print(f"concurrency={c}: {args.requests_per_level} requests...", flush=True)
        level = run_level(args.base_url, args.model, c, args.requests_per_level, args.max_tokens)
        level["cost_per_mtok_usd"] = cost_per_mtok(
            level["aggregate_tokens_per_s"], args.gpu_hourly_usd
        )
        print(json.dumps(level), flush=True)
        levels.append(level)

    run = {
        "model": args.model,
        "base_url": args.base_url,
        "max_tokens": args.max_tokens,
        "requests_per_level": args.requests_per_level,
        "gpu": args.gpu,
        "gpu_hourly_usd": args.gpu_hourly_usd,
        "date": args.date or "unset",
        "levels": levels,
    }
    if args.output_json:
        with open(args.output_json, "w") as f:
            json.dump(run, f, indent=2)
    if args.output_md:
        with open(args.output_md, "w") as f:
            f.write(to_markdown(run))
    print("done")


if __name__ == "__main__":
    main()
