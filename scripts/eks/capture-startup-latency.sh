#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
require_cmd kubectl
require_cmd curl

ensure_experiment_dir >/dev/null

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
ARTIFACT_DIR="${EXPERIMENT_DIR}"
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${ARTIFACT_DIR}/results}"
mkdir -p "${RESULTS_DIR}"

service_name=""
auth_header=()

case "${LANE}" in
  ray-vllm)
    service_name="ray-vllm-serve-svc"
    ;;
  dynamo-vllm|k8s-vllm)
    service_name="llm-service"
    if [[ -n "${VLLM_API_KEY:-}" ]]; then
      auth_header=(-H "Authorization: Bearer ${VLLM_API_KEY}")
    fi
    ;;
  *)
    echo '{"status":"skipped","reason":"unsupported_lane"}' > "${RESULTS_DIR}/startup-latency.json"
    exit 0
    ;;
esac

kubectl -n "${NAMESPACE}" get svc "${service_name}" >/dev/null 2>&1 || {
  echo '{"status":"skipped","reason":"service_not_found"}' > "${RESULTS_DIR}/startup-latency.json"
  exit 0
}

kubectl -n "${NAMESPACE}" port-forward svc/"${service_name}" "${LOCAL_PORT}:8000" >/tmp/startup-latency-port-forward.log 2>&1 &
pf_pid=$!
trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' EXIT

start_epoch="$(date +%s)"
health_ready="false"
models_ready="false"
health_elapsed="null"
models_elapsed="null"

for _ in $(seq 1 360); do
  now_epoch="$(date +%s)"
  elapsed="$((now_epoch - start_epoch))"

  if [[ "${health_ready}" != "true" ]]; then
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1; then
      health_ready="true"
      health_elapsed="${elapsed}"
    fi
  fi

  if [[ "${models_ready}" != "true" ]]; then
    if [[ ${#auth_header[@]} -gt 0 ]]; then
      curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models" "${auth_header[@]}" >/dev/null 2>&1
    else
      curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models" >/dev/null 2>&1
    fi
    if [[ $? -eq 0 ]]; then
      models_ready="true"
      models_elapsed="${elapsed}"
    fi
  fi

  if [[ "${health_ready}" == "true" && "${models_ready}" == "true" ]]; then
    break
  fi

  sleep 5
done

cat > "${RESULTS_DIR}/startup-latency.json" <<EOF
{
  "status": "ok",
  "lane": "${LANE}",
  "namespace": "${NAMESPACE}",
  "service": "${service_name}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "health_ready": ${health_ready},
  "health_ready_seconds": ${health_elapsed},
  "models_ready": ${models_ready},
  "models_ready_seconds": ${models_elapsed}
}
EOF
