#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd helm
require_cmd kubectl

accelerator_type="${ACCELERATOR_TYPE:-nvidia}"

case "${accelerator_type}" in
  nvidia)
    helm repo add nvdp https://nvidia.github.io/k8s-device-plugin >/dev/null
    helm repo update >/dev/null
    helm upgrade --install nvdp nvdp/nvidia-device-plugin --namespace nvidia --create-namespace --set gfd.enabled=true
    ;;
  neuron)
    helm upgrade --install neuron-helm-chart oci://public.ecr.aws/neuron/neuron-helm-chart --namespace kube-system --set npd.enabled=false
    ;;
  *)
    echo "Unsupported accelerator_type: ${accelerator_type}" >&2
    exit 1
    ;;
esac
