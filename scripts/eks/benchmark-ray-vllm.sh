#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
METRICS_PORT="${METRICS_PORT:-18081}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
TASK_SUITE="${TASK_SUITE:-0}"
BENCHMARK_ROUNDS="${BENCHMARK_ROUNDS:-2}"
BENCHMARK_CONCURRENCY="${BENCHMARK_CONCURRENCY:-2}"
API_KEY="${VLLM_API_KEY:-EMPTY}"
ARTIFACT_DIR="${EXPERIMENT_DIR:-/tmp}"
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${ARTIFACT_DIR}/results}"

mkdir -p "${ARTIFACT_DIR}"
mkdir -p "${RESULTS_DIR}"

benchmark_start_ts="$(python3 -c 'import time; print(f"{time.time():.3f}")')"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=1800s
worker_nodes="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | sed '/^$/d' | wc -l | tr -d ' ')"
worker_gpus="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{.items[*].metadata.name}' | wc -w | tr -d ' ')"
head_pod="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${NAMESPACE}" port-forward "pod/${head_pod}" "${LOCAL_PORT}:8000" "${METRICS_PORT}:8080" >/tmp/ray-vllm-benchmark-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models" >/dev/null 2>&1 && break
  sleep 2
done

benchmark_args=(
  --base-url "http://127.0.0.1:${LOCAL_PORT}"
  --metrics-url "http://127.0.0.1:${METRICS_PORT}/metrics"
  --api-key "${API_KEY}"
  --prompt "${PROMPT}"
  --max-tokens "${MAX_TOKENS}"
  --rounds "${BENCHMARK_ROUNDS}"
  --concurrency "${BENCHMARK_CONCURRENCY}"
  --worker-nodes "${worker_nodes}"
  --worker-gpus "${worker_gpus}"
)

if [[ "${TASK_SUITE}" == "1" ]]; then
  benchmark_args+=(--task-suite)
fi

python3 "${ROOT_DIR}/scripts/eks/benchmark_vllm.py" \
  "${benchmark_args[@]}" | tee "${RESULTS_DIR}/benchmark-ray-vllm.json"

benchmark_end_ts="$(python3 -c 'import time; print(f"{time.time():.3f}")')"

cat > "${RESULTS_DIR}/benchmark-window.json" <<EOF
{
  "lane": "ray-vllm",
  "start_time_unix": ${benchmark_start_ts},
  "end_time_unix": ${benchmark_end_ts},
  "duration_seconds": $(python3 -c 'import sys; print(float(sys.argv[2]) - float(sys.argv[1]))' "${benchmark_start_ts}" "${benchmark_end_ts}")
}
EOF

if [[ -n "${EXPERIMENT_DIR:-}" ]]; then
  {
    echo "lane=ray-vllm"
    echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "local_port=${LOCAL_PORT}"
    echo "task_suite=${TASK_SUITE}"
    echo "max_tokens=${MAX_TOKENS}"
    echo "benchmark_rounds=${BENCHMARK_ROUNDS}"
    echo "benchmark_concurrency=${BENCHMARK_CONCURRENCY}"
  } > "${RESULTS_DIR}/benchmark-ray-vllm.meta"
fi
