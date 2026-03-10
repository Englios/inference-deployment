#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl
require_cmd python3

MANIFEST_TEMPLATE="${EKS_DIR}/ray/templates/nvidia-smi-all-gpus-pod.yaml.tpl"

gpu_nodes=()
while IFS= read -r node; do
  [[ -n "${node}" ]] && gpu_nodes+=("${node}")
done < <(kubectl get nodes -l accelerator=nvidia-gpu,workload=inference -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

if [[ "${#gpu_nodes[@]}" -eq 0 ]]; then
  echo "No inference GPU nodes found." >&2
  exit 1
fi

cleanup() {
  for node in "${gpu_nodes[@]}"; do
    pod_name="nvidia-smi-$(cut -d. -f1 <<<"${node}" | tr '[:upper:]' '[:lower:]')"
    kubectl delete pod "${pod_name}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  done
}

trap cleanup EXIT

for node in "${gpu_nodes[@]}"; do
  pod_name="nvidia-smi-$(cut -d. -f1 <<<"${node}" | tr '[:upper:]' '[:lower:]')"
  gpu_count="$(kubectl get node "${node}" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')"

  if [[ -z "${gpu_count}" || "${gpu_count}" == "<none>" ]]; then
    echo "Node ${node} does not advertise allocatable GPUs yet." >&2
    exit 1
  fi

  kubectl delete pod "${pod_name}" --ignore-not-found --wait >/dev/null 2>&1 || true

  MANIFEST_TEMPLATE="${MANIFEST_TEMPLATE}" POD_NAME="${pod_name}" NODE_NAME="${node}" GPU_COUNT="${gpu_count}" python3 - <<'PY' | kubectl apply -f -
import os
from pathlib import Path

template = Path(os.environ["MANIFEST_TEMPLATE"]).read_text()
rendered = (template
    .replace("${POD_NAME}", os.environ["POD_NAME"])
    .replace("${NODE_NAME}", os.environ["NODE_NAME"])
    .replace("${GPU_COUNT}", os.environ["GPU_COUNT"]))
print(rendered)
PY

  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/"${pod_name}" --timeout=300s
  echo "===== ${node} (${gpu_count} GPUs) ====="
  kubectl logs "${pod_name}"
done
