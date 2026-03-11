#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
require_cmd kubectl
ensure_experiment_dir >/dev/null
RESULTS_DIR="${EXPERIMENT_RESULTS_DIR:-${EXPERIMENT_DIR}/results}"
mkdir -p "${RESULTS_DIR}"

capture_topology_file() {
  local output_file
  output_file="${RESULTS_DIR}/topology.txt"
  "$@" | tee "${output_file}"
}

case "${LANE}" in
  ray-vllm)
    capture_topology_file "${ROOT_DIR}/scripts/eks/report-ray-topology.sh"
    ;;
  dynamo-vllm)
    capture_topology_file "${ROOT_DIR}/scripts/eks/report-dynamo-topology.sh"
    ;;
  k8s-vllm)
    kubectl -n "${NAMESPACE:-inference-engine}" get pod -l app=vllm-server -o wide | tee "${RESULTS_DIR}/topology.txt"
    ;;
  *)
    fail_lane_not_implemented
    ;;
esac
