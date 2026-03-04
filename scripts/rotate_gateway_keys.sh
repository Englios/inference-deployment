#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-inference-engine}"
SECRET_NAME="${SECRET_NAME:-vllm-secrets}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-middleware-gateway}"
KEY_PREFIX="${KEY_PREFIX:-user}"
GENERATE_COUNT="${GENERATE_COUNT:-2}"
ROLL_RESTART="${ROLL_RESTART:-true}"

usage() {
  cat <<'EOF'
Rotate/replace middleware client API keys in Kubernetes.

Usage:
  scripts/rotate_gateway_keys.sh [KEY1 [KEY2 ...]]

Behavior:
  - If keys are provided: uses exactly those keys.
  - If no keys are provided: generates GENERATE_COUNT random keys.
  - Writes keys to secret field MIDDLEWARE_API_KEYS (comma-separated).
  - Optionally restarts middleware deployment and waits for rollout.

Environment overrides:
  NAMESPACE=inference-engine
  SECRET_NAME=vllm-secrets
  DEPLOYMENT_NAME=middleware-gateway
  KEY_PREFIX=user
  GENERATE_COUNT=2
  ROLL_RESTART=true

Examples:
  scripts/rotate_gateway_keys.sh
  scripts/rotate_gateway_keys.sh alice-key bob-key
  NAMESPACE=inference-engine GENERATE_COUNT=3 scripts/rotate_gateway_keys.sh
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
require_cmd openssl

if [[ "$#" -gt 0 ]]; then
  KEYS=("$@")
else
  if ! [[ "$GENERATE_COUNT" =~ ^[0-9]+$ ]] || [[ "$GENERATE_COUNT" -lt 1 ]]; then
    echo "GENERATE_COUNT must be a positive integer" >&2
    exit 1
  fi
  KEYS=()
  for _ in $(seq 1 "$GENERATE_COUNT"); do
    KEYS+=("${KEY_PREFIX}-$(openssl rand -hex 8)")
  done
fi

joined_keys="$(printf '%s,' "${KEYS[@]}")"
joined_keys="${joined_keys%,}"

echo "Patching secret ${SECRET_NAME} in namespace ${NAMESPACE} ..."
kubectl -n "$NAMESPACE" patch secret "$SECRET_NAME" --type merge -p "{\"stringData\":{\"MIDDLEWARE_API_KEYS\":\"${joined_keys}\"}}" >/dev/null

echo "Updated MIDDLEWARE_API_KEYS with ${#KEYS[@]} key(s)."

if [[ "$ROLL_RESTART" == "true" ]]; then
  echo "Restarting deployment ${DEPLOYMENT_NAME} ..."
  kubectl -n "$NAMESPACE" rollout restart "deploy/${DEPLOYMENT_NAME}" >/dev/null
  kubectl -n "$NAMESPACE" rollout status "deploy/${DEPLOYMENT_NAME}" --timeout=180s
fi

echo
echo "Active client keys:"
for k in "${KEYS[@]}"; do
  echo "- ${k}"
done

echo
echo "Example usage:"
echo "curl -sS -k -H 'Host: llm.example.com' -H 'Authorization: Bearer ${KEYS[0]}' https://100.96.172.63/v1/models"
