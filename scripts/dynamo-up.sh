#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-inference-engine}"
WORKER_NAME="${WORKER_NAME:-VllmDecodeWorker}"
KUBE_DIR="${KUBE_DIR:-.kube/vllm-dynamo}"
WAIT="${WAIT:-true}"
TIMEOUT="${TIMEOUT:-600}"

usage() {
  cat <<'EOF'
Deploy/redeploy the Dynamo inference worker.

Usage:
  scripts/dynamo-up.sh

Behavior:
  - Applies the kustomize manifests (kubectl apply -k) to update the CR.
  - Bounces the worker pod so the operator picks up any arg/config changes.
  - Optionally waits for the worker pod to become Ready.

Environment overrides:
  NAMESPACE=inference-engine
  WORKER_NAME=VllmDecodeWorker
  KUBE_DIR=.kube/vllm-dynamo
  WAIT=true          (set to false to skip waiting)
  TIMEOUT=600        (seconds to wait for Ready)

Examples:
  scripts/dynamo-up.sh
  WAIT=false scripts/dynamo-up.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kubectl

echo "Applying manifests from ${KUBE_DIR} ..."
kubectl apply -k "$KUBE_DIR"

echo "Bouncing worker pod to pick up changes ..."
kubectl -n "$NAMESPACE" delete pod \
  -l "dynamo-component=${WORKER_NAME}" \
  --ignore-not-found

echo "Operator is reconciling ..."

if [[ "$WAIT" == "true" ]]; then
  echo "Waiting up to ${TIMEOUT}s for worker pod to become Ready ..."
  # Give the operator a moment to create the new pod before we wait on it
  sleep 5
  kubectl -n "$NAMESPACE" wait pod \
    -l "dynamo-component=${WORKER_NAME}" \
    --for=condition=Ready \
    --timeout="${TIMEOUT}s"
  echo "Worker is Ready."
else
  echo "Skipping wait. Check status with:"
  echo "  kubectl -n ${NAMESPACE} get pods -l dynamo-component=${WORKER_NAME}"
fi
