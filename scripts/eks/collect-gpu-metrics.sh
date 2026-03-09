#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-inference-engine}"

echo "==> Ray worker placement"
kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o wide
echo

echo "==> GPU usage per Ray worker pod"
for pod in $(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{.items[*].metadata.name}'); do
  echo "--- ${pod} ---"
  kubectl -n "${NAMESPACE}" exec "${pod}" -- nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw --format=csv,noheader,nounits || true
  echo
done
