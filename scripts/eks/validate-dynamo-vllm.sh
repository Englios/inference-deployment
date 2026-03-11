#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd curl

NAMESPACE="${NAMESPACE:-$(config_value namespace)}"
LOCAL_PORT="${LOCAL_PORT:-18000}"
METRICS_PORT="${METRICS_PORT:-18001}"
DYNAMO_GRAPH_NAME="${DYNAMO_GRAPH_NAME:-$(config_value dynamo.graph_name)}"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l "nvidia.com/dynamo-graph-deployment-name=${DYNAMO_GRAPH_NAME}" --timeout=1800s
kubectl -n "${NAMESPACE}" port-forward svc/llm-service "${LOCAL_PORT}:80" "${METRICS_PORT}:9090" >/tmp/dynamo-vllm-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1 && break
  sleep 2
done

curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health"; echo
curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models"; echo
kubectl -n "${NAMESPACE}" get pod -l "nvidia.com/dynamo-graph-deployment-name=${DYNAMO_GRAPH_NAME}" -o wide
