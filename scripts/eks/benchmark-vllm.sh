#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3
require_env VLLM_API_KEY

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18000}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"

kubectl -n "${NAMESPACE}" rollout status statefulset/vllm-server --timeout=1800s
kubectl -n "${NAMESPACE}" port-forward svc/llm-service "${LOCAL_PORT}:80" >/tmp/vllm-benchmark-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

python3 "${ROOT_DIR}/scripts/eks/benchmark_vllm.py" \
  --base-url "http://127.0.0.1:${LOCAL_PORT}" \
  --api-key "${VLLM_API_KEY}" \
  --prompt "${PROMPT}" \
  --max-tokens "${MAX_TOKENS}"
