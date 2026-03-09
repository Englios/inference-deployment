#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-inference-engine}"

echo "==> Ray worker pods by node"
kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
echo

echo "==> Worker count per node"
kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
