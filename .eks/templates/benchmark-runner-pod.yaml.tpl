apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  nodeSelector:
    accelerator: nvidia-gpu
    workload: inference
  tolerations:
  - key: dedicated
    operator: Equal
    value: inference
    effect: NoSchedule
  containers:
  - name: benchmark-runner
    image: python:3.12-slim
    command: ["bash", "-lc", "sleep infinity"]
