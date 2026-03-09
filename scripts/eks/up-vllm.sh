#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_env HF_TOKEN
require_env VLLM_API_KEY

run_step "Bring up EKS cluster" "${ROOT_DIR}/scripts/eks/up.sh"
run_step "Deploy vLLM" "${ROOT_DIR}/scripts/eks/deploy-vllm.sh"
run_step "Validate vLLM" "${ROOT_DIR}/scripts/eks/validate-vllm.sh"
