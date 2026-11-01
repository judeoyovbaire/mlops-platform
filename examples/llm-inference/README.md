# LLM Inference with vLLM on KServe (JDH-376)

Real vLLM serving on real GPUs, with an honest benchmark. The previous
version of this example had never been launched - it forced FLASH_ATTN on
hardware that aborts on it, carried Knative annotations under
RawDeployment, and its nodeSelector matched no node the platform creates.
This version is built for the platform's actual GPU strategy (JDH-375).

## What deploys

`kserve-vllm.yaml` - two configurations of the same ungated Apache-2.0
model, one g5.xlarge (NVIDIA A10G 24GB, spot) each:

| InferenceService | Model | Precision | Why |
|---|---|---|---|
| `llm-qwen-bf16` | Qwen/Qwen2.5-7B-Instruct | bfloat16 | baseline |
| `llm-qwen-awq` | Qwen/Qwen2.5-7B-Instruct-AWQ | AWQ 4-bit | the production default |

Both pin their HuggingFace revision to a commit SHA (immutable refs for
models - the same principle the platform enforces for image tags).

Why A10G and not L4: **eu-west-1 offers no g6/L4 instances** (verified via
AWS spot advisor data). The A10G matches the L4's 24GB with ~2x the memory
bandwidth and full FlashAttention-2 support - benchmarks stay representative.

## Prerequisites

1. **Spot-G quota**: `All G and VT Spot Instance Requests` >= 4 vCPUs
   (8 to run both configs concurrently). Fresh accounts have 0 - request
   an increase and wait for approval before any session.
2. **nvidia-device-plugin**: installed by the platform
   (`aws-platform/gpu.tf`) - without it, GPU nodes boot with drivers but
   Kubernetes never sees `nvidia.com/gpu`.
3. The Karpenter GPU pool (spot-only, g5 only, 4h node expiry) ships with
   the platform.

## Run a benchmark session

```bash
# The OpenAI routes (/v1/*) require a Bearer token (vLLM --api-key via
# VLLM_API_KEY). Without the Secret the pods sit in CreateContainerConfigError.
export VLLM_API_KEY=$(openssl rand -hex 24)
kubectl create secret generic vllm-api-key -n mlops \
  --from-literal=api-key="$VLLM_API_KEY" --dry-run=client -o yaml | kubectl apply -f -
# In a new shell, recover the key instead of generating a new one:
#   export VLLM_API_KEY=$(kubectl get secret vllm-api-key -n mlops -o jsonpath='{.data.api-key}' | base64 -d)

kubectl apply -f kserve-vllm.yaml
kubectl wait --for=condition=Ready inferenceservice/llm-qwen-bf16 -n mlops --timeout=900s
# node ~2 min (spot), image pull + model download + load ~5-8 min

SVC=$(kubectl get svc -n mlops -l serving.kserve.io/inferenceservice=llm-qwen-bf16 -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n mlops svc/$SVC 8080:80 &

# llm_bench.py reads the token from $VLLM_API_KEY (or pass --api-key)
python ../../scripts/benchmark/llm_bench.py \
  --base-url http://localhost:8080 --model qwen25-7b \
  --concurrency 1,4,8,16 --requests-per-level 24 \
  --gpu-hourly-usd 0.77 --date $(date -u +%F) \
  --output-json results/bf16.json --output-md results/bf16.md
# repeat against llm-qwen-awq with --model qwen25-7b-awq
```

The harness measures TTFT p50/p95, end-to-end latency, per-request decode
speed, aggregate throughput (the continuous-batching payoff), and derives
**$/Mtok** from the spot rate - the number that makes GPU serving
economics concrete. Results are committed under `results/`.

The key gates `/v1/*` only: vLLM also serves `/invocations`, `/pause` and
`/abort_requests` without auth (its `docs/usage/security.md`), so the
endpoint stays ClusterIP-only and is reached by port-forward. Prefix caching
is on by default and the prompts cycle, so TTFT after the first pass of each
level includes cache hits; read p50 TTFT with that in mind.

## Session economics (measured 2026-07-14)

- g5.xlarge spot: ~$0.77/hr (eu-west-1c cheapest AZ)
- Full benchmark session (both configs, 4 concurrency levels): ~2-3 GPU
  hours ~= **$5 of GPU** + cluster base
- Karpenter expires GPU nodes after 4h; an AWS Budget configured manually
  in the account (not managed by this repo) alarms at 50%/100% of the
  monthly cap

## Cleanup

```bash
kubectl delete -f kserve-vllm.yaml
kubectl delete secret vllm-api-key -n mlops
# node consolidates away within ~1 minute of the last GPU pod terminating
```
