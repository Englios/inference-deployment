#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-inference-engine}"

echo "==> Ray head pod"
kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
echo

echo "==> Ray worker pods by node"
kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
echo

echo "==> Distinct nodes participating in PP topology"
{ kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'; kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}'; } | sort | uniq -c
