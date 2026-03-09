#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd helm
require_cmd kubectl

helm repo add kuberay https://ray-project.github.io/kuberay-helm/ >/dev/null
helm repo update >/dev/null
helm upgrade --install kuberay-operator kuberay/kuberay-operator \
  --namespace kuberay-system \
  --create-namespace \
  --set-string nodeSelector."kubernetes\.io/os"=linux \
  --set-string nodeSelector.workload=system
