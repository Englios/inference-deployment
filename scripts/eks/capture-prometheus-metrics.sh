#!/usr/bin/env bash
# Capture GPU, token, and network metrics from Prometheus in a single port-forward session.
# This is equivalent to running capture-gpu-metrics.sh + capture-token-metrics.sh +
# capture-network-metrics.sh but with shared setup/teardown overhead.

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
require_cmd kubectl
require_cmd python3

ensure_experiment_dir >/dev/null

NAMESPACE="${NAMESPACE:-inference-engine}"
PROM_NAMESPACE="${PROM_NAMESPACE:-monitoring}"
PROM_SERVICE="${PROM_SERVICE:-kube-prometheus-stack-prometheus}"
PROM_LOCAL_PORT="${PROM_LOCAL_PORT:-19090}"
ARTIFACT_DIR="${EXPERIMENT_DIR}"
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${ARTIFACT_DIR}/results}"
METRICS_DIR="${EXPERIMENT_METRICS_DIR:-${ARTIFACT_DIR}/metrics}"
WINDOW_FILE="${RESULTS_DIR}/benchmark-window.json"

GPU_PATH="${METRICS_DIR}/gpu-metrics.json"
TOKEN_PATH="${METRICS_DIR}/token-metrics.json"
NETWORK_PATH="${METRICS_DIR}/network-metrics.json"

mkdir -p "${METRICS_DIR}"

# Check Prometheus service is present before attempting port-forward
if ! kubectl -n "${PROM_NAMESPACE}" get svc "${PROM_SERVICE}" >/dev/null 2>&1; then
  for path in "${GPU_PATH}" "${TOKEN_PATH}" "${NETWORK_PATH}"; do
    echo '{"status":"skipped","reason":"prometheus_service_not_found"}' > "${path}"
  done
  exit 0
fi

kubectl -n "${PROM_NAMESPACE}" port-forward svc/"${PROM_SERVICE}" "${PROM_LOCAL_PORT}:9090" \
  >/tmp/prometheus-metrics-port-forward.log 2>&1 &
pf_pid=$!
trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' EXIT

ready=false
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/-/ready" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done

if [[ "${ready}" != "true" ]]; then
  for path in "${GPU_PATH}" "${TOKEN_PATH}" "${NETWORK_PATH}"; do
    echo '{"status":"skipped","reason":"prometheus_not_ready"}' > "${path}"
  done
  exit 0
fi

PROM_ARGS=(
  --base-url "http://127.0.0.1:${PROM_LOCAL_PORT}"
  --window-file "${WINDOW_FILE}"
  --default-range-seconds 300
  --step-seconds 5
)

echo "==> Capturing GPU metrics"
python3 "${ROOT_DIR}/scripts/eks/prometheus_window_export.py" \
  "${PROM_ARGS[@]}" \
  --query "gpu_util_pct=avg(DCGM_FI_DEV_GPU_UTIL)" \
  --query "gpu_util_pct_by_node=avg by (Hostname) (DCGM_FI_DEV_GPU_UTIL)" \
  --query "gpu_mem_mb=max(DCGM_FI_DEV_FB_USED)" \
  --query "gpu_mem_mb_by_node=max by (Hostname) (DCGM_FI_DEV_FB_USED)" \
  --query "gpu_power_w=avg(DCGM_FI_DEV_POWER_USAGE)" \
  --query "gpu_power_w_by_node=avg by (Hostname) (DCGM_FI_DEV_POWER_USAGE)" \
  --query "gpu_temp_c=max(DCGM_FI_DEV_GPU_TEMP)" \
  --query "gpu_temp_c_by_node=max by (Hostname) (DCGM_FI_DEV_GPU_TEMP)" \
  > "${GPU_PATH}"

echo "==> Capturing token/request metrics"
python3 "${ROOT_DIR}/scripts/eks/prometheus_window_export.py" \
  "${PROM_ARGS[@]}" \
  --query "ray_ongoing_requests=sum(ray_serve_num_ongoing_http_requests)" \
  --query "ray_queue_len=sum(ray_serve_request_router_queue_len)" \
  --query "ray_http_rps=sum(rate(ray_serve_num_http_requests_total[1m]))" \
  --query "ray_deployment_rps=sum(rate(ray_serve_deployment_request_counter_total[1m]))" \
  > "${TOKEN_PATH}"

echo "==> Capturing network metrics"
python3 "${ROOT_DIR}/scripts/eks/prometheus_window_export.py" \
  "${PROM_ARGS[@]}" \
  --query "pod_rx_bps=sum(rate(container_network_receive_bytes_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "pod_tx_bps=sum(rate(container_network_transmit_bytes_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "pod_drop_pps=sum(rate(container_network_receive_packets_dropped_total{namespace=\"${NAMESPACE}\"}[2m])) + sum(rate(container_network_transmit_packets_dropped_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "node_rx_bps=sum(rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_rx_bps_by_node=sum by (instance) (rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_tx_bps=sum(rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_tx_bps_by_node=sum by (instance) (rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  > "${NETWORK_PATH}"
