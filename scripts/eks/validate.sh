#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

accelerator_type="${ACCELERATOR_TYPE:-nvidia}"

kubectl get nodes -L accelerator,workload,node.kubernetes.io/accelerator

case "${accelerator_type}" in
  nvidia)
    kubectl get ds -n nvidia
    kubectl get nodes "-o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"
    kubectl delete pod nvidia-smi --ignore-not-found --wait >/dev/null 2>&1 || true
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-smi
  namespace: default
spec:
  restartPolicy: Never
  tolerations:
  - key: dedicated
    operator: Equal
    value: inference
    effect: NoSchedule
  nodeSelector:
    accelerator: nvidia-gpu
    workload: inference
  containers:
  - name: gpu-demo
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["/bin/sh", "-c"]
    args: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/nvidia-smi --timeout=300s
    kubectl logs nvidia-smi
    ;;
  neuron)
    kubectl get ds -n kube-system neuron-device-plugin
    kubectl get nodes "-o=custom-columns=NAME:.metadata.name,NEURON:.status.allocatable.aws\.amazon\.com/neuron"
    ;;
esac
