#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_env HF_TOKEN

run_step "Bring up EKS cluster" "${ROOT_DIR}/scripts/eks/up.sh"
run_step "Install monitoring stack" "${ROOT_DIR}/scripts/eks/install-monitoring.sh"
run_step "Install KubeRay" "${ROOT_DIR}/scripts/eks/install-kuberay.sh"
run_step "Deploy Ray-backed vLLM" "${ROOT_DIR}/scripts/eks/deploy-ray-vllm.sh"
run_step "Expose Ray/vLLM metrics" "${ROOT_DIR}/scripts/eks/expose-ray-metrics.sh"
run_step "Validate Ray-backed vLLM" "${ROOT_DIR}/scripts/eks/validate-ray-vllm.sh"
run_step "Validate monitoring stack" "${ROOT_DIR}/scripts/eks/validate-monitoring.sh"
run_step "Report Ray topology" "${ROOT_DIR}/scripts/eks/report-ray-topology.sh"
