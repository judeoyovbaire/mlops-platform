# LLM Inference with vLLM on KServe

This example demonstrates deploying a Large Language Model (LLM) for inference using vLLM and KServe on the MLOps platform.

## Overview

[vLLM](https://github.com/vllm-project/vllm) is a high-throughput LLM inference engine that provides:
- **PagedAttention**: Efficient memory management for KV cache
- **Continuous batching**: Dynamic batching for improved throughput
- **Tensor parallelism**: Distribute models across multiple GPUs
- **OpenAI-compatible API**: Drop-in replacement for OpenAI endpoints

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client App    │────▶│     KServe       │────▶│     vLLM        │
│                 │     │  InferenceService│     │   (GPU Pod)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │                        │
                               ▼                        ▼
                        ┌─────────────┐          ┌──────────────┐
                        │  Prometheus │          │  HuggingFace │
                        │  Metrics    │          │  Model Hub   │
                        └─────────────┘          └──────────────┘
```

## Prerequisites

- GPU node pool with NVIDIA GPUs (g4dn.xlarge or larger)
- At least 16GB GPU memory for 7B models
- NVIDIA GPU Operator installed (or GPU-enabled AMI)

## Quick Start

### 1. Deploy the InferenceService

```bash
# Deploy Mistral-7B-Instruct (requires ~14GB GPU memory)
kubectl apply -f kserve-vllm.yaml

# Check status
kubectl get inferenceservice llm-mistral -n mlops

# Wait for ready
kubectl wait --for=condition=Ready inferenceservice/llm-mistral -n mlops --timeout=600s
```

### 2. Test the Endpoint

```bash
# Port forward (or use ALB URL)
kubectl port-forward svc/llm-mistral-predictor -n mlops 8080:80 &

# Test with OpenAI-compatible API
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.2",
    "prompt": "Explain kubernetes in one sentence:",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

### 3. Chat Completions (OpenAI-compatible)

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.2",
    "messages": [
      {"role": "user", "content": "What is MLOps?"}
    ],
    "max_tokens": 200
  }'
```

## Model Options

| Model | Size | GPU Memory | Instance Type | Use Case |
|-------|------|------------|---------------|----------|
| `TinyLlama/TinyLlama-1.1B-Chat-v1.0` | 1.1B | ~4GB | g4dn.xlarge | Testing, demos |
| `microsoft/phi-2` | 2.7B | ~6GB | g4dn.xlarge | Code, reasoning |
| `mistralai/Mistral-7B-Instruct-v0.2` | 7B | ~14GB | g4dn.xlarge | General purpose |
| `meta-llama/Llama-2-7b-chat-hf` | 7B | ~14GB | g4dn.xlarge | Chat (requires license) |
| `codellama/CodeLlama-7b-Instruct-hf` | 7B | ~14GB | g4dn.xlarge | Code generation |
| `mistralai/Mixtral-8x7B-Instruct-v0.1` | 46.7B | ~90GB | p4d.24xlarge | High quality (multi-GPU) |

## Configuration

### GPU Resources

```yaml
# kserve-vllm.yaml
resources:
  limits:
    nvidia.com/gpu: "1"        # Number of GPUs
  requests:
    cpu: "4"
    memory: "16Gi"
```

### vLLM Arguments

```yaml
args:
  - --model=mistralai/Mistral-7B-Instruct-v0.2
  - --max-model-len=4096       # Context length
  - --gpu-memory-utilization=0.9
  - --dtype=float16            # or bfloat16 for newer GPUs
  - --tensor-parallel-size=1   # Increase for multi-GPU
```

### Autoscaling

```yaml
# Scale based on GPU utilization or request latency
annotations:
  autoscaling.knative.dev/target: "10"         # Concurrent requests
  autoscaling.knative.dev/metric: "concurrency"
  autoscaling.knative.dev/minScale: "0"        # Scale to zero
  autoscaling.knative.dev/maxScale: "3"
```

## Production Considerations

### 1. Model Caching

Pre-download models to avoid cold start delays:

```yaml
# Use a PVC with the model pre-loaded
volumeMounts:
  - name: model-cache
    mountPath: /root/.cache/huggingface
volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-cache
```

### 2. Request Batching

vLLM handles batching automatically, but tune for your workload:

```yaml
args:
  - --max-num-seqs=256         # Max concurrent sequences
  - --max-num-batched-tokens=8192
```

### 3. Monitoring

Key metrics to track:
- `vllm:num_requests_running` - Active requests
- `vllm:num_requests_waiting` - Queue depth
- `vllm:gpu_cache_usage_perc` - KV cache utilization
- `vllm:avg_generation_throughput_toks_per_s` - Tokens/second

### 4. Cost Optimization

- Use **SPOT instances** for non-critical workloads
- Enable **scale-to-zero** for dev/staging
- Use smaller models (TinyLlama, Phi-2) for testing
- Consider **quantized models** (AWQ, GPTQ) for reduced memory

## Comparison: vLLM vs Other Serving Options

| Feature | vLLM | TGI | Triton | TensorRT-LLM |
|---------|------|-----|--------|--------------|
| Throughput | High | High | Very High | Very High |
| Ease of Use | Easy | Easy | Complex | Complex |
| OpenAI API | Yes | Yes | Custom | Custom |
| Quantization | AWQ, GPTQ | GPTQ | All | All |
| Multi-GPU | Yes | Yes | Yes | Yes |
| KServe Support | Native | Native | Native | Custom |

## Troubleshooting

### Model Download Timeout

```bash
# Increase timeout for large models
kubectl patch inferenceservice llm-mistral -n mlops --type=merge -p '
  {"spec":{"predictor":{"timeout":1800}}}'
```

### Out of Memory

```bash
# Use quantized model
--model=TheBloke/Mistral-7B-Instruct-v0.2-AWQ
--quantization=awq
```

### Check Logs

```bash
kubectl logs -f deployment/llm-mistral-predictor -n mlops
```

## Files

- `kserve-vllm.yaml` - KServe InferenceService for vLLM
- `test_llm.py` - Python test script
- `requirements.txt` - Dependencies

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe LLM Runtime](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/)
- [HuggingFace Model Hub](https://huggingface.co/models)