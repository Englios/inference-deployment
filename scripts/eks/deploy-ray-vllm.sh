#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

MANIFEST_DIR="${ROOT_DIR}/.kube/eks/ray"
NAMESPACE="${NAMESPACE:-inference-engine}"
RAY_MANIFEST="${RAY_MANIFEST:-${MANIFEST_DIR}/ray-vllm-service.yaml}"

require_env HF_TOKEN

kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
kubectl -n "${NAMESPACE}" create secret generic ray-vllm-secrets \
  --from-literal=HF_TOKEN="${HF_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${RAY_MANIFEST}"
