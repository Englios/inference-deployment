#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane
require_cmd kubectl
require_cmd python3

ensure_experiment_dir >/dev/null

NAMESPACE="${NAMESPACE:-inference-engine}"
ARTIFACT_DIR="${EXPERIMENT_DIR}"
METRICS_DIR="${EXPERIMENT_METRICS_DIR:-${ARTIFACT_DIR}/metrics}"
PROM_DIR="${EXPERIMENT_METRICS_PROM_DIR:-${METRICS_DIR}/prometheus}"

mkdir -p "${PROM_DIR}"
PROM_NAMESPACE="${PROM_NAMESPACE:-monitoring}"
PROM_SERVICE="${PROM_SERVICE:-kube-prometheus-stack-prometheus}"
PROM_LOCAL_PORT="${PROM_LOCAL_PORT:-19090}"

kubectl -n "${PROM_NAMESPACE}" get svc "${PROM_SERVICE}" >/dev/null 2>&1 || {
  echo "Prometheus service ${PROM_NAMESPACE}/${PROM_SERVICE} not found; skipping Prometheus snapshot." >&2
  PROM_SERVICE=""
}

kubectl -n "${NAMESPACE}" get pods -o wide > "${METRICS_DIR}/observed-pods.txt" || true
kubectl -n "${NAMESPACE}" get svc > "${METRICS_DIR}/observed-services.txt" || true
kubectl -n monitoring get pods > "${METRICS_DIR}/observed-monitoring-pods.txt" || true
kubectl get nodes -o json > "${METRICS_DIR}/observed-nodes.json" || true
kubectl version --short > "${METRICS_DIR}/observed-k8s-version.txt" || true

cluster_gpu_node_count="$(kubectl get nodes -l accelerator=nvidia-gpu,workload=inference --no-headers 2>/dev/null | wc -l | tr -d ' ' || true)"
cluster_gpu_allocatable_total="$(kubectl get nodes -l accelerator=nvidia-gpu,workload=inference -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk '{sum+=$1} END {print sum+0}' || true)"

lane_worker_selector=""
if [[ "${LANE}" == "ray-vllm" ]]; then
  lane_worker_selector='ray.io/group=gpu-workers'
elif [[ "${LANE}" == "dynamo-vllm" ]]; then
  lane_worker_selector='nvidia.com/dynamo-component-type=worker'
elif [[ "${LANE}" == "k8s-vllm" ]]; then
  lane_worker_selector='app=vllm-server'
fi

lane_worker_pod_count="0"
lane_worker_node_count="0"
lane_worker_gpu_limit_total="0"

if [[ -n "${lane_worker_selector}" ]]; then
  lane_worker_pod_count="$(kubectl -n "${NAMESPACE}" get pod -l "${lane_worker_selector}" --no-headers 2>/dev/null | wc -l | tr -d ' ' || true)"
  lane_worker_node_count="$(kubectl -n "${NAMESPACE}" get pod -l "${lane_worker_selector}" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | sed '/^$/d' | wc -l | tr -d ' ' || true)"
  lane_worker_gpu_limit_total="$(kubectl -n "${NAMESPACE}" get pod -l "${lane_worker_selector}" -o jsonpath='{range .items[*]}{.spec.containers[0].resources.limits.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk '{sum+=$1} END {print sum+0}' || true)"
fi

cat > "${ARTIFACT_DIR}/topology-metadata.json" <<EOF
{
  "lane": "${LANE}",
  "namespace": "${NAMESPACE}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster_gpu_node_count": ${cluster_gpu_node_count:-0},
  "cluster_gpu_allocatable_total": ${cluster_gpu_allocatable_total:-0},
  "lane_worker_selector": "${lane_worker_selector}",
  "lane_worker_pod_count": ${lane_worker_pod_count:-0},
  "lane_worker_node_count": ${lane_worker_node_count:-0},
  "lane_worker_gpu_limit_total": ${lane_worker_gpu_limit_total:-0}
}
EOF

if [[ "${LANE}" == "ray-vllm" ]]; then
  kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o wide > "${METRICS_DIR}/observed-ray-head.txt" || true
  kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o wide > "${METRICS_DIR}/observed-ray-workers.txt" || true

  while IFS= read -r pod; do
    [[ -z "${pod}" ]] && continue
    {
      echo "--- ${pod} ---"
      kubectl -n "${NAMESPACE}" exec "${pod}" -- nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw --format=csv,noheader,nounits || true
      echo
    } >> "${METRICS_DIR}/observed-gpu-nvidia-smi.txt"
  done < <(kubectl -n "${NAMESPACE}" get pod -l ray.io/group=gpu-workers -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')
elif [[ "${LANE}" == "dynamo-vllm" ]]; then
  kubectl -n "${NAMESPACE}" get pod -l nvidia.com/dynamo-component-type=frontend -o wide > "${METRICS_DIR}/observed-dynamo-frontend.txt" || true
  kubectl -n "${NAMESPACE}" get pod -l nvidia.com/dynamo-component-type=worker -o wide > "${METRICS_DIR}/observed-dynamo-workers.txt" || true

  while IFS= read -r pod; do
    [[ -z "${pod}" ]] && continue
    {
      echo "--- ${pod} ---"
      kubectl -n "${NAMESPACE}" exec "${pod}" -- nvidia-smi --query-gpu=index,name,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw --format=csv,noheader,nounits || true
      echo
    } >> "${METRICS_DIR}/observed-gpu-nvidia-smi.txt"
  done < <(kubectl -n "${NAMESPACE}" get pod -l nvidia.com/dynamo-component-type=worker -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')
fi

if [[ -n "${PROM_SERVICE}" ]]; then
  kubectl -n "${PROM_NAMESPACE}" port-forward svc/"${PROM_SERVICE}" "${PROM_LOCAL_PORT}:9090" >/tmp/observed-prom-port-forward.log 2>&1 &
  pf_pid=$!
  trap 'kill "${pf_pid}" >/dev/null 2>&1 || true' EXIT

  sleep 2
  if curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/-/ready" >/dev/null 2>&1; then
    curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/api/v1/targets" > "${PROM_DIR}/observed-prometheus-targets.json" || true
    curl -fsS "http://127.0.0.1:${PROM_LOCAL_PORT}/api/v1/rules" > "${PROM_DIR}/observed-prometheus-rules.json" || true
  fi
fi
