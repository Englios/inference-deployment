#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
kubectl get svc -n monitoring kube-prometheus-stack-prometheus kube-prometheus-stack-grafana
kubectl get svc -n monitoring dcgm-exporter >/dev/null 2>&1 && kubectl get svc -n monitoring dcgm-exporter
kubectl get svc -n monitoring loki-gateway >/dev/null 2>&1 && kubectl get svc -n monitoring loki-gateway

kubectl get pod -n monitoring -l app.kubernetes.io/name=promtail >/dev/null 2>&1 && kubectl get pod -n monitoring -l app.kubernetes.io/name=promtail

if kubectl get namespace inference-engine >/dev/null 2>&1; then
  kubectl get svc -n inference-engine ray-head-metrics >/dev/null 2>&1 && kubectl get svc -n inference-engine ray-head-metrics
  kubectl get svc -n inference-engine ray-vllm-head >/dev/null 2>&1 && kubectl get svc -n inference-engine ray-vllm-head
  kubectl get servicemonitor -n monitoring ray-head-metrics >/dev/null 2>&1 && kubectl get servicemonitor -n monitoring ray-head-metrics
  kubectl get servicemonitor -n monitoring ray-vllm-head >/dev/null 2>&1 && kubectl get servicemonitor -n monitoring ray-vllm-head
  kubectl get podmonitor -n monitoring dynamo-frontend >/dev/null 2>&1 && kubectl get podmonitor -n monitoring dynamo-frontend
  kubectl get podmonitor -n monitoring dynamo-worker >/dev/null 2>&1 && kubectl get podmonitor -n monitoring dynamo-worker
  kubectl get servicemonitor -n monitoring dynamo-llm-service >/dev/null 2>&1 && kubectl get servicemonitor -n monitoring dynamo-llm-service
fi
