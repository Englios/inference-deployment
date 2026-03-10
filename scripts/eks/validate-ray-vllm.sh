#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd curl

NAMESPACE="${NAMESPACE:-inference-engine}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
RAY_SERVICE_NAME="${RAY_SERVICE_NAME:-ray-vllm}"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=900s
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/group=gpu-workers --timeout=900s

head_node="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].spec.nodeName}')"
worker_node_count="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')"
distinct_nodes="$({ printf '%s\n' "${head_node}"; kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'; } | sort -u | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "${worker_node_count}" -lt 1 || "${distinct_nodes}" -lt 2 ]]; then
  echo "Expected Ray PP topology to span 2 distinct nodes (head + worker), got ${distinct_nodes}." >&2
  kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o wide
  kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o wide
  exit 1
fi

head_pod="$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "${NAMESPACE}" port-forward "pod/${head_pod}" "${LOCAL_PORT}:8000" >/tmp/ray-vllm-port-forward.log 2>&1 &
port_forward_pid=$!

trap 'kill "${port_forward_pid}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1 && break
  sleep 5
done

curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health"; echo
curl -fsS "http://127.0.0.1:${LOCAL_PORT}/v1/models"; echo
kubectl -n "${NAMESPACE}" get rayservice "${RAY_SERVICE_NAME}"
kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o wide
kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o wide
