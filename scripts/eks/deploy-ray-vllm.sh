#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

MANIFEST_DIR="${EKS_DIR}/ray"
NAMESPACE="${NAMESPACE:-inference-engine}"
RAY_MANIFEST="${RAY_MANIFEST:-${EKS_RENDERED_DIR}/ray/ray-vllm-service.yaml}"

python3 "${ROOT_DIR}/scripts/eks/inference_config.py" \
  --config "${EKS_INFERENCE_CONFIG}" \
  --lane ray-vllm \
  --output-root "${EKS_RENDERED_DIR}" >/dev/null

kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
kubectl -n "${NAMESPACE}" create secret generic ray-vllm-secrets \
  --from-literal=HF_TOKEN="${HF_TOKEN:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${RAY_MANIFEST}"
