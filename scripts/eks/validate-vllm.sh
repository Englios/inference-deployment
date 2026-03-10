#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd curl

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18000}"
VLLM_API_KEY="${VLLM_API_KEY:-}"

require_env VLLM_API_KEY

kubectl -n "${NAMESPACE}" rollout status deployment/vllm-server --timeout=1800s
kubectl -n "${NAMESPACE}" port-forward svc/llm-service "${LOCAL_PORT}:80" >/tmp/vllm-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1 && break; sleep 2; done

curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health"; echo
curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models" -H "Authorization: Bearer ${VLLM_API_KEY}"; echo
kubectl -n "${NAMESPACE}" get pod -l app=vllm-server -o wide
