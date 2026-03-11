#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3
require_env VLLM_API_KEY

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18000}"
METRICS_PORT="${METRICS_PORT:-18001}"
PROMPT="${PROMPT:-Explain tensor parallelism and why TTFT matters for user experience.}"
MAX_TOKENS="${MAX_TOKENS:-256}"
TASK_SUITE="${TASK_SUITE:-0}"
BENCHMARK_ROUNDS="${BENCHMARK_ROUNDS:-2}"
BENCHMARK_CONCURRENCY="${BENCHMARK_CONCURRENCY:-2}"
ARTIFACT_DIR="${EXPERIMENT_DIR:-/tmp}"
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${ARTIFACT_DIR}/results}"

mkdir -p "${ARTIFACT_DIR}"
mkdir -p "${RESULTS_DIR}"

benchmark_start_ts="$(python3.11 -c 'import time; print(f"{time.time():.3f}")')"

kubectl -n "${NAMESPACE}" rollout status deployment/vllm-server --timeout=1800s
kubectl -n "${NAMESPACE}" port-forward svc/llm-service "${LOCAL_PORT}:80" "${METRICS_PORT}:8000" >/tmp/vllm-benchmark-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models" -H "Authorization: Bearer ${VLLM_API_KEY}" >/dev/null 2>&1 && break
  sleep 2
done

benchmark_args=(
  --base-url "http://127.0.0.1:${LOCAL_PORT}"
  --metrics-url "http://127.0.0.1:${METRICS_PORT}/metrics"
  --api-key "${VLLM_API_KEY}"
  --prompt "${PROMPT}"
  --max-tokens "${MAX_TOKENS}"
  --rounds "${BENCHMARK_ROUNDS}"
  --concurrency "${BENCHMARK_CONCURRENCY}"
)

if [[ "${TASK_SUITE}" == "1" ]]; then
  benchmark_args+=(--task-suite)
fi

python3.11 "${ROOT_DIR}/scripts/eks/benchmark_vllm.py" \
  "${benchmark_args[@]}" | tee "${RESULTS_DIR}/benchmark-k8s-vllm.json"

benchmark_end_ts="$(python3.11 -c 'import time; print(f"{time.time():.3f}")')"

cat > "${RESULTS_DIR}/benchmark-window.json" <<EOF
{
  "lane": "k8s-vllm",
  "start_time_unix": ${benchmark_start_ts},
  "end_time_unix": ${benchmark_end_ts},
  "duration_seconds": $(python3.11 -c 'import sys; print(float(sys.argv[2]) - float(sys.argv[1]))' "${benchmark_start_ts}" "${benchmark_end_ts}")
}
EOF

if [[ -n "${EXPERIMENT_DIR:-}" ]]; then
  {
    echo "lane=k8s-vllm"
    echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "local_port=${LOCAL_PORT}"
    echo "task_suite=${TASK_SUITE}"
    echo "max_tokens=${MAX_TOKENS}"
    echo "benchmark_rounds=${BENCHMARK_ROUNDS}"
    echo "benchmark_concurrency=${BENCHMARK_CONCURRENCY}"
  } > "${RESULTS_DIR}/benchmark-k8s-vllm.meta"
fi
