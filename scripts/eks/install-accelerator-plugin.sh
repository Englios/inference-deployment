#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd helm
require_cmd kubectl

kubectl label nodes -l accelerator=nvidia-gpu,workload=inference nvidia.com/gpu.present=true --overwrite

helm repo add nvdp https://nvidia.github.io/k8s-device-plugin >/dev/null
helm repo update >/dev/null
helm upgrade --install nvdp nvdp/nvidia-device-plugin \
  --namespace nvidia \
  --create-namespace \
  --set gfd.enabled=true \
  --set-json 'affinity={}' \
  --set-string nodeSelector.accelerator=nvidia-gpu \
  --set-string nodeSelector.workload=inference \
  --set tolerations[0].key=dedicated \
  --set tolerations[0].operator=Equal \
  --set tolerations[0].value=inference \
  --set tolerations[0].effect=NoSchedule \
  --set tolerations[1].key=nvidia.com/gpu \
  --set tolerations[1].operator=Exists \
  --set tolerations[1].effect=NoSchedule
