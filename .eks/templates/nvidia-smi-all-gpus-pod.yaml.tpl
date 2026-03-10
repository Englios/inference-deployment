apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: default
spec:
  restartPolicy: Never
  nodeName: ${NODE_NAME}
  tolerations:
  - key: dedicated
    operator: Equal
    value: inference
    effect: NoSchedule
  containers:
  - name: nvidia-smi
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["bash", "-lc", "nvidia-smi -L && echo '---' && nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: ${GPU_COUNT}
