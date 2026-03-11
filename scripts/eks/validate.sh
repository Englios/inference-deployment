#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

ENABLE_NVIDIA_SMI_PROBE="${ENABLE_NVIDIA_SMI_PROBE:-false}"

kubectl get nodes -L accelerator,workload,node.kubernetes.io/accelerator

kubectl get ds -n nvidia
kubectl get nodes "-o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"

if [[ "${ENABLE_NVIDIA_SMI_PROBE}" != "true" ]]; then
  exit 0
fi

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
