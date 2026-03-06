# OpenAI-Compatible Middleware Gateway

This app runs as a lightweight gateway in front of the internal LLM service.

- Validates client auth (`MIDDLEWARE_API_KEYS` or `MIDDLEWARE_API_KEY`, optional)
- Adds upstream auth (`INTERNAL_LLM_API_KEY`)
- Optionally injects a system prompt (`SYSTEM_PROMPT`)
- Proxies OpenAI-compatible routes to `llm-service`

## File layout

- `app.py` — FastAPI gateway
- `Dockerfile` — container build

## Local run (uv)

```bash
cd app
uv pip install --system fastapi==0.116.1 httpx==0.28.1 uvicorn==0.35.0

export UPSTREAM_BASE_URL="http://127.0.0.1:10000"
export INTERNAL_LLM_API_KEY="supersecretkey"
export MIDDLEWARE_API_KEYS="alice-key,bob-key"
export SYSTEM_PROMPT="You are a helpful assistant."

uvicorn app:app --host 0.0.0.0 --port 8080
```

Upstream URL precedence:

1. `UPSTREAM_BASE_URL` (runtime override)
2. `DEFAULT_UPSTREAM_BASE_URL` (image/runtime default)
3. fallback: `http://127.0.0.1:8000`

## Docker build and push

```bash
docker build \
  --build-arg DEFAULT_UPSTREAM_BASE_URL=http://llm-service.inference-engine.svc.cluster.local \
  -t ghcr.io/englios/openai-llm-gateway:latest app

docker push ghcr.io/englios/openai-llm-gateway:latest
```

## Quick endpoint tests

```bash
curl http://127.0.0.1:8080/health

curl http://127.0.0.1:8080/v1/models \
  -H "Authorization: Bearer alice-key"

curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer bob-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","messages":[{"role":"user","content":"hello"}]}'
```

## Kubernetes notes

This app is deployed via `.kube/middleware` and currently pinned to the Debian node.
Ingress routes public traffic to `middleware-service`, and the gateway forwards to:

`http://llm-service.inference-engine.svc.cluster.local`

The middleware deployment uses rolling update with graceful termination (`preStop` + `terminationGracePeriodSeconds`) to reduce transient errors during key-rotation rollouts.
It runs with 2 replicas so one pod can keep serving while the other restarts.

Rotate client keys with one command:

```bash
scripts/rotate_gateway_keys.sh
```

Or set explicit keys:

```bash
scripts/rotate_gateway_keys.sh alice-key bob-key team-key
```
