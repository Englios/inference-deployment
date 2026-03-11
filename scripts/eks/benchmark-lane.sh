#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
ensure_experiment_dir >/dev/null
record_experiment_metadata

case "${LANE}" in
  ray-vllm)
    exec "${ROOT_DIR}/scripts/eks/benchmark-ray-vllm.sh"
    ;;
  k8s-vllm)
    exec "${ROOT_DIR}/scripts/eks/benchmark-vllm.sh"
    ;;
  dynamo-vllm)
    exec "${ROOT_DIR}/scripts/eks/benchmark-dynamo-vllm.sh"
    ;;
  *)
    fail_lane_not_implemented
    ;;
esac
