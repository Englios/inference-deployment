#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

OVERLAY_DIR="${ROOT_DIR}/.kube/eks/vllm"
NAMESPACE="${NAMESPACE:-inference-engine}"

require_env HF_TOKEN
require_env VLLM_API_KEY

kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${NAMESPACE}"

kubectl -n "${NAMESPACE}" create secret generic vllm-secrets \
  --from-literal=HF_TOKEN="${HF_TOKEN}" \
  --from-literal=VLLM_API_KEY="${VLLM_API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -k "${OVERLAY_DIR}"
kubectl -n "${NAMESPACE}" rollout status deploy/vllm-server --timeout=900s
