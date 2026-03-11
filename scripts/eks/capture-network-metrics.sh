#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
require_cmd kubectl
require_cmd python3.11

ensure_experiment_dir >/dev/null

NAMESPACE="${NAMESPACE:-inference-engine}"
PROM_NAMESPACE="${PROM_NAMESPACE:-monitoring}"
PROM_SERVICE="${PROM_SERVICE:-kube-prometheus-stack-prometheus}"
PROM_LOCAL_PORT="${PROM_LOCAL_PORT:-19090}"
ARTIFACT_DIR="${EXPERIMENT_DIR}"
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${ARTIFACT_DIR}/results}"
METRICS_DIR="${EXPERIMENT_METRICS_DIR:-${ARTIFACT_DIR}/metrics}"
NETWORK_PATH="${METRICS_DIR}/network-metrics.json"
WINDOW_FILE="${RESULTS_DIR}/benchmark-window.json"

mkdir -p "${METRICS_DIR}"

kubectl -n "${PROM_NAMESPACE}" get svc "${PROM_SERVICE}" >/dev/null 2>&1 || {
  echo '{"status":"skipped","reason":"prometheus_service_not_found"}' > "${NETWORK_PATH}"
  exit 0
}

kubectl -n "${PROM_NAMESPACE}" port-forward svc/"${PROM_SERVICE}" "${PROM_LOCAL_PORT}:9090" >/tmp/network-metrics-port-forward.log 2>&1 &
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
  echo '{"status":"skipped","reason":"prometheus_not_ready"}' > "${NETWORK_PATH}"
  exit 0
fi

python3.11 "${ROOT_DIR}/scripts/eks/prometheus_window_export.py" \
  --base-url "http://127.0.0.1:${PROM_LOCAL_PORT}" \
  --window-file "${WINDOW_FILE}" \
  --default-range-seconds 300 \
  --step-seconds 5 \
  --query "pod_rx_bps=sum(rate(container_network_receive_bytes_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "pod_tx_bps=sum(rate(container_network_transmit_bytes_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "pod_drop_pps=sum(rate(container_network_receive_packets_dropped_total{namespace=\"${NAMESPACE}\"}[2m])) + sum(rate(container_network_transmit_packets_dropped_total{namespace=\"${NAMESPACE}\"}[2m]))" \
  --query "node_rx_bps=sum(rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_rx_bps_by_node=sum by (instance) (rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_tx_bps=sum(rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  --query "node_tx_bps_by_node=sum by (instance) (rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[2m]))" \
  > "${NETWORK_PATH}"
