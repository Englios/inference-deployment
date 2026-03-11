#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3
require_env HF_TOKEN

python3 "${ROOT_DIR}/scripts/eks/inference_config.py" \
  --config "${EKS_INFERENCE_CONFIG}" \
  --lane dynamo-vllm \
  --output-root "${EKS_RENDERED_DIR}" >/dev/null

namespace="$(config_value namespace)"

kubectl apply -f "${EKS_RENDERED_DIR}/dynamo/namespace.yaml"
kubectl -n "${namespace}" create secret generic hf-token-secret \
  --from-literal=HF_TOKEN="${HF_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${EKS_RENDERED_DIR}/dynamo/model-cache-pvc.yaml"
kubectl apply -f "${EKS_RENDERED_DIR}/dynamo/vllm/agg.yaml"
kubectl apply -f "${EKS_RENDERED_DIR}/dynamo/service-llm.yaml"
