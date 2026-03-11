#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd helm
require_cmd kubectl

MONITORING_DIR="${EKS_DIR}/monitoring"
PROM_STACK_VERSION="${PROM_STACK_VERSION:-69.8.2}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-prom-operator}"
ENABLE_DCGM_EXPORTER="${ENABLE_DCGM_EXPORTER:-auto}"
ENABLE_LOKI="${ENABLE_LOKI:-true}"
LOKI_STACK_VERSION="${LOKI_STACK_VERSION:-6.54.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-6.16.6}"
PROM_STORAGE_CLASS="${PROM_STORAGE_CLASS:-auto}"

gpu_node_count="$(kubectl get nodes -l accelerator=nvidia-gpu,workload=inference --no-headers 2>/dev/null | wc -l | tr -d ' ')"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

prom_stack_args=(
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack
  --namespace monitoring
  --create-namespace
  --version "${PROM_STACK_VERSION}"
  -f "${MONITORING_DIR}/kube-prometheus-stack-values.yaml"
  --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}"
)

if [[ "${PROM_STORAGE_CLASS}" == "auto" ]]; then
  default_sc="$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' | head -n1)"
  if [[ -z "${default_sc}" ]]; then
    default_sc="$(kubectl get storageclass gp2 -o jsonpath='{.metadata.name}' 2>/dev/null || true)"
  fi
  if [[ -n "${default_sc}" ]]; then
    prom_stack_args+=(--set "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=${default_sc}")
  fi
elif [[ -n "${PROM_STORAGE_CLASS}" ]]; then
  prom_stack_args+=(--set "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=${PROM_STORAGE_CLASS}")
fi

"${prom_stack_args[@]}"

if [[ "${ENABLE_DCGM_EXPORTER}" == "true" || ( "${ENABLE_DCGM_EXPORTER}" == "auto" && "${gpu_node_count}" != "0" ) ]]; then
  dcgm_args=(
    helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter
    --namespace monitoring
    --create-namespace
    -f "${MONITORING_DIR}/dcgm-exporter-values.yaml"
  )

  if [[ -n "${DCGM_NODE_SELECTOR_KEY:-}" && -n "${DCGM_NODE_SELECTOR_VALUE:-}" ]]; then
    dcgm_args+=(--set "nodeSelector.${DCGM_NODE_SELECTOR_KEY}=${DCGM_NODE_SELECTOR_VALUE}")
  fi

  "${dcgm_args[@]}"
else
  helm uninstall dcgm-exporter --namespace monitoring >/dev/null 2>&1 || true
fi

if [[ "${ENABLE_LOKI}" == "true" ]]; then
  helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --create-namespace \
    --version "${LOKI_STACK_VERSION}" \
    -f "${MONITORING_DIR}/loki-values.yaml"

  helm upgrade --install promtail grafana/promtail \
    --namespace monitoring \
    --create-namespace \
    --version "${PROMTAIL_VERSION}" \
    -f "${MONITORING_DIR}/promtail-values.yaml"
else
  helm uninstall promtail --namespace monitoring >/dev/null 2>&1 || true
  helm uninstall loki --namespace monitoring >/dev/null 2>&1 || true
fi

kubectl apply -f "${MONITORING_DIR}/grafana-dashboard-loki-logs.yaml"
kubectl apply -f "${MONITORING_DIR}/grafana-dashboard-inference-overview.yaml"
kubectl apply -f "${MONITORING_DIR}/grafana-dashboard-gpu-token-metrics.yaml"
kubectl apply -f "${MONITORING_DIR}/grafana-dashboard-network-comparison.yaml"
