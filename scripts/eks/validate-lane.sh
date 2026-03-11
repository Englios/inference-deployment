#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
ensure_experiment_dir >/dev/null
record_experiment_metadata
capture_cluster_snapshot

run_step "Validate base cluster" "${ROOT_DIR}/scripts/eks/validate.sh"
run_step "Validate monitoring stack" "${ROOT_DIR}/scripts/eks/validate-monitoring.sh"

case "${LANE}" in
  ray-vllm)
    exec "${ROOT_DIR}/scripts/eks/validate-ray-vllm.sh"
    ;;
  k8s-vllm)
    exec "${ROOT_DIR}/scripts/eks/validate-vllm.sh"
    ;;
  dynamo-vllm)
    exec "${ROOT_DIR}/scripts/eks/validate-dynamo-vllm.sh"
    ;;
  *)
    fail_lane_not_implemented
    ;;
esac
