#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-inference-engine}"
WORKER_NAME="${WORKER_NAME:-VllmDecodeWorker}"
WAIT="${WAIT:-true}"
TIMEOUT="${TIMEOUT:-120}"

usage() {
  cat <<'EOF'
Stop the Dynamo inference worker pod, freeing the GPU.

Usage:
  scripts/dynamo-down.sh

Behavior:
  - Deletes the worker pod directly. The operator will not recreate it
    until dynamo-up.sh is run again (apply + bounce).
  - Does NOT delete PVCs, secrets, configmaps, or any other resources.
  - Optionally waits for the pod to be fully gone.

Environment overrides:
  NAMESPACE=inference-engine
  WORKER_NAME=VllmDecodeWorker
  WAIT=true          (set to false to skip waiting)
  TIMEOUT=120        (seconds to wait for pod termination)

Examples:
  scripts/dynamo-down.sh
  WAIT=false scripts/dynamo-down.sh
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

echo "Stopping worker pod (${WORKER_NAME}) in namespace ${NAMESPACE} ..."

kubectl -n "$NAMESPACE" delete pod \
  -l "dynamo-component=${WORKER_NAME}" \
  --ignore-not-found

if [[ "$WAIT" == "true" ]]; then
  echo "Waiting up to ${TIMEOUT}s for worker pod to terminate ..."
  kubectl -n "$NAMESPACE" wait pod \
    -l "dynamo-component=${WORKER_NAME}" \
    --for=delete \
    --timeout="${TIMEOUT}s" 2>/dev/null || true
  echo "Worker is down. GPU is free."
else
  echo "Skipping wait. Check status with:"
  echo "  kubectl -n ${NAMESPACE} get pods -l dynamo-component=${WORKER_NAME}"
fi
