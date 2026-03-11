#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

python3 "${ROOT_DIR}/scripts/eks/inference_config.py" \
  --config "${EKS_INFERENCE_CONFIG}" \
  --lane dynamo-vllm \
  --output-root "${EKS_RENDERED_DIR}" >/dev/null

kubectl apply -f "${EKS_RENDERED_DIR}/monitoring/dynamo-frontend-podmonitor.yaml"
kubectl apply -f "${EKS_RENDERED_DIR}/monitoring/dynamo-worker-podmonitor.yaml"
kubectl apply -f "${EKS_RENDERED_DIR}/monitoring/dynamo-llm-servicemonitor.yaml"
