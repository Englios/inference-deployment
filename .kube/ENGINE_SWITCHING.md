# One-Engine-at-a-Time Switching Guide

This repo supports three inference engines in namespace `inference-engine`:

- `vllm` in `.kube/vllm-vanilla`
- `sglang` in `.kube/sglang-vanilla`
- `llama.cpp` in `.kube/llamacpp-vanilla`
- middleware/auth gateway in `.kube/middleware`

Shared resources are in `.kube/base`:

- namespace
- shared model cache PVC (`model-cache-pvc`)
- shared engine-agnostic config (`config.yaml`)
- `api-keys-secret`

All three reuse the same PVC `model-cache-pvc`.

## Cache warmup job (shared base)

Base now includes `.kube/base/model-download.yaml` as a one-shot model cache warmup job.
It reads model settings from `inference-engine-config`:

- `MODEL_DOWNLOAD_NAME`
- `MODEL_DOWNLOAD_REVISION`
- `HF_HOME`
- `HF_HUB_ENABLE_HF_TRANSFER`

Run warmup before starting any engine:

```bash
kubectl apply -k .kube/base
kubectl -n inference-engine delete job model-download --ignore-not-found
kubectl -n inference-engine apply -f .kube/base/model-download.yaml
kubectl -n inference-engine logs -f job/model-download
kubectl -n inference-engine wait --for=condition=complete --timeout=30m job/model-download
```

## Node placement

Current mapping in manifests:

- `vllm` -> `inference-node=pop-os`
- `sglang` -> `inference-node=pop-os`
- `llama.cpp` -> `inference-node=pop-os`
- `middleware-gateway` -> `inference-node=debian`

Apply node labels once:

```bash
kubectl label node pop-os inference-node=pop-os --overwrite
kubectl label node debian inference-node=debian --overwrite
```

To change placement, edit each deployment `nodeSelector.inference-node`.

## Middleware layer on Debian

Deploy the middleware/auth app layer on Debian:

```bash
kubectl -n inference-engine create secret docker-registry ghcr-pull-secret \
	--docker-server=ghcr.io \
	--docker-username=<github-username> \
	--docker-password=<github-pat-with-read:packages> \
	--dry-run=client -o yaml | kubectl apply -f -

kubectl apply -k .kube/middleware
kubectl -n inference-engine rollout status deploy/middleware-gateway
```

Internal service URL:

```text
http://middleware-service.inference-engine.svc.cluster.local
```

Build and push middleware image before deploy:

```bash
docker build -t ghcr.io/englios/openai-llm-gateway:latest app
docker push ghcr.io/englios/openai-llm-gateway:latest
```

OpenAI-compatible endpoints exposed by middleware:

- `GET /v1/models`
- `POST /v1/chat/completions`
- passthrough for other `/v1/*` routes

## 1) Stop currently running engine

```bash
kubectl -n inference-engine scale deploy/vllm-server --replicas=0 || true
kubectl -n inference-engine scale deploy/sglang-server --replicas=0 || true
kubectl -n inference-engine scale deploy/llamacpp-server --replicas=0 || true
```

## 2) Start selected engine

### Start vLLM

```bash
kubectl apply -k .kube/vllm-vanilla
kubectl -n inference-engine scale deploy/vllm-server --replicas=1
kubectl -n inference-engine rollout status deploy/vllm-server
```

### Start SGLang

```bash
kubectl apply -k .kube/sglang-vanilla
kubectl -n inference-engine scale deploy/sglang-server --replicas=1
kubectl -n inference-engine rollout status deploy/sglang-server
```

### Start llama.cpp

```bash
kubectl apply -k .kube/llamacpp-vanilla
kubectl -n inference-engine scale deploy/llamacpp-server --replicas=1
kubectl -n inference-engine rollout status deploy/llamacpp-server
```

## 3) Test locally with port-forward

```bash
kubectl -n inference-engine port-forward svc/llm-service 18000:80
```

Then test health:

```bash
curl http://127.0.0.1:18000/health
```

## Notes

- Keep `.kube/base/secrets.yaml` local-only and out of git.
- Keep `.kube/base/config.yaml` engine-agnostic for shared knobs only.
- Use `MODEL_DOWNLOAD_NAME` as the shared model identifier for vLLM/SGLang and cache warmup.
- Keep engine-specific runtime tuning values in each engine deployment manifest.
- Use `MODEL_DOWNLOAD_*` keys to pre-warm the shared PVC cache.
- `vllm` uses startup/readiness/liveness probes; readiness checks `/v1/models` with API key so traffic starts only after model load.
- `sglang` uses startup/readiness/liveness probes; readiness checks `/v1/models` with API key.
- `llama.cpp` uses startup/readiness/liveness probes via `/health`.
- `llama.cpp` manifest expects a GGUF file at `/models/llamacpp/model.gguf`.
- For `sglang`/`vllm`, model artifacts are pulled into shared cache under `/models`.
- All engines use the `LLM_API_KEY` env var sourced from `api-keys-secret` in the cluster.

Probe debug:

```bash
kubectl -n inference-engine describe pod -l app=vllm-server | sed -n '/Readiness/,/Events/p'
```
