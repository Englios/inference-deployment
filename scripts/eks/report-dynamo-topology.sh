#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-$(config_value namespace)}"
DYNAMO_GRAPH_NAME="${DYNAMO_GRAPH_NAME:-$(config_value dynamo.graph_name)}"

echo "==> Dynamo frontend pods"
kubectl -n "${NAMESPACE}" get pod -l "nvidia.com/dynamo-graph-deployment-name=${DYNAMO_GRAPH_NAME},nvidia.com/dynamo-component-type=frontend" -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
echo

echo "==> Dynamo worker pods"
kubectl -n "${NAMESPACE}" get pod -l "nvidia.com/dynamo-graph-deployment-name=${DYNAMO_GRAPH_NAME},nvidia.com/dynamo-component-type=worker" -o custom-columns='POD:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP'
echo

echo "==> Distinct nodes participating"
kubectl -n "${NAMESPACE}" get pod -l "nvidia.com/dynamo-graph-deployment-name=${DYNAMO_GRAPH_NAME}" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
