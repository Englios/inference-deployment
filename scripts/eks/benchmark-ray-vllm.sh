#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
TASK_SUITE="${TASK_SUITE:-0}"
API_KEY="${VLLM_API_KEY:-EMPTY}"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=1800s
worker_nodes="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | sed '/^$/d' | wc -l | tr -d ' ')"
worker_gpus="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{.items[*].metadata.name}' | wc -w | tr -d ' ')"
head_pod="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${NAMESPACE}" port-forward "pod/${head_pod}" "${LOCAL_PORT}:8000" >/tmp/ray-vllm-benchmark-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

benchmark_args=(
  --base-url "http://127.0.0.1:${LOCAL_PORT}"
  --api-key "${API_KEY}"
  --prompt "${PROMPT}"
  --max-tokens "${MAX_TOKENS}"
  --worker-nodes "${worker_nodes}"
  --worker-gpus "${worker_gpus}"
)

if [[ "${TASK_SUITE}" == "1" ]]; then
  benchmark_args+=(--task-suite)
fi

python3 "${ROOT_DIR}/scripts/eks/benchmark_vllm.py" \
  "${benchmark_args[@]}"
