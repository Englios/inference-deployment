#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd helm
require_cmd kubectl

MONITORING_DIR="${EKS_DIR}/monitoring"
PROM_STACK_VERSION="${PROM_STACK_VERSION:-69.8.2}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --version "${PROM_STACK_VERSION}" \
  -f "${MONITORING_DIR}/kube-prometheus-stack-values.yaml"

helm upgrade --install dcgm-exporter gpu-helm-charts/dcgm-exporter \
  --namespace monitoring \
  --create-namespace \
  -f "${MONITORING_DIR}/dcgm-exporter-values.yaml"
