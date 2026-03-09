#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3
require_env VLLM_API_KEY

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=1800s
head_pod="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${NAMESPACE}" port-forward "pod/${head_pod}" "${LOCAL_PORT}:8000" >/tmp/ray-vllm-benchmark-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

python3 "${ROOT_DIR}/scripts/eks/benchmark_vllm.py" \
  --base-url "http://127.0.0.1:${LOCAL_PORT}" \
  --api-key "${VLLM_API_KEY}" \
  --prompt "${PROMPT}" \
  --max-tokens "${MAX_TOKENS}"
