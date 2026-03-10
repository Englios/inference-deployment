#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

MONITORING_DIR="${EKS_DIR}/monitoring"

kubectl apply -f "${MONITORING_DIR}/ray-metrics-service.yaml"
kubectl apply -f "${MONITORING_DIR}/ray-metrics-servicemonitor.yaml"
kubectl apply -f "${MONITORING_DIR}/vllm-head-service.yaml"
kubectl apply -f "${MONITORING_DIR}/vllm-head-servicemonitor.yaml"
