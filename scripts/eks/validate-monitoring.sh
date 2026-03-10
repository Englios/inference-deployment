#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
kubectl get svc -n monitoring kube-prometheus-stack-prometheus kube-prometheus-stack-grafana dcgm-exporter
kubectl get svc -n inference-engine ray-head-metrics ray-vllm-head
kubectl get servicemonitor -n monitoring ray-head-metrics ray-vllm-head
