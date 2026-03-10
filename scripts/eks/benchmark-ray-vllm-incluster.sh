#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

NAMESPACE="${NAMESPACE:-inference-engine}"
POD_NAME="${POD_NAME:-ray-vllm-benchmark-runner}"
SERVICE_URL="${SERVICE_URL:-http://ray-vllm-serve-svc.${NAMESPACE}.svc.cluster.local:8000}"
TASK_SUITE="${TASK_SUITE:-1}"
API_KEY="${VLLM_API_KEY:-EMPTY}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
MANIFEST_TEMPLATE="${EKS_DIR}/ray/templates/benchmark-runner-pod.yaml.tpl"
BENCH_SCRIPT_PATH="${ROOT_DIR}/scripts/eks/benchmark_vllm.py"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=1800s
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/group=gpu-workers --timeout=1800s

kubectl -n "${NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found --wait >/dev/null 2>&1 || true

NAMESPACE="${NAMESPACE}" POD_NAME="${POD_NAME}" MANIFEST_TEMPLATE="${MANIFEST_TEMPLATE}" python3 - <<'PY' | kubectl apply -f -
import os
from pathlib import Path

template = Path(os.environ["MANIFEST_TEMPLATE"]).read_text()
rendered = (template
    .replace("${POD_NAME}", os.environ["POD_NAME"])
    .replace("${NAMESPACE}", os.environ["NAMESPACE"]))
print(rendered)
PY

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/"${POD_NAME}" --timeout=300s

kubectl -n "${NAMESPACE}" cp "${BENCH_SCRIPT_PATH}" "${POD_NAME}:/tmp/benchmark_vllm.py"

worker_nodes="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | sed '/^$/d' | wc -l | tr -d ' ')"
worker_gpus="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.containers[0].resources.limits.nvidia\.com/gpu}{"\n"}{end}' | awk '{sum+=$1} END {print sum+0}')"

benchmark_args=(
  python3 /tmp/benchmark_vllm.py
  --base-url "${SERVICE_URL}"
  --api-key "${API_KEY}"
  --prompt "${PROMPT}"
  --max-tokens "${MAX_TOKENS}"
  --worker-nodes "${worker_nodes}"
  --worker-gpus "${worker_gpus}"
)

if [[ "${TASK_SUITE}" == "1" ]]; then
  benchmark_args+=(--task-suite)
fi

kubectl -n "${NAMESPACE}" exec "${POD_NAME}" -- "${benchmark_args[@]}"
