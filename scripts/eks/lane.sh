#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

LANE="${LANE:-ray-vllm}"

lane_slug() {
  printf '%s' "${LANE}"
}

lane_results_dir() {
  local timestamp month_bucket run_id
  timestamp="${EXPERIMENT_TIMESTAMP:-$(date +%Y-%m-%dT%H-%M-%S)}"
  month_bucket="$(date +%Y-%m)"

  if [[ "${timestamp}" =~ ^([0-9]{4}-[0-9]{2})-[0-9]{2}T ]]; then
    month_bucket="${BASH_REMATCH[1]}"
  fi

  run_id="run-${timestamp}"
  printf '%s' "${ROOT_DIR}/experiments/${LANE}/runs/${month_bucket}/${run_id}"
}

active_experiment_dir() {
  if [[ -n "${EXPERIMENT_DIR:-}" ]]; then
    printf '%s' "${EXPERIMENT_DIR}"
    return
  fi
  lane_results_dir
}

ensure_experiment_dir() {
  local dir
  dir="$(active_experiment_dir)"
  mkdir -p "${dir}"
  export EXPERIMENT_DIR="${dir}"
  export EXPERIMENT_RESULTS_DIR="${EXPERIMENT_DIR}/results"
  export EXPERIMENT_METRICS_DIR="${EXPERIMENT_DIR}/metrics"
  export EXPERIMENT_METRICS_PROM_DIR="${EXPERIMENT_METRICS_DIR}/prometheus"
  export EXPERIMENT_GRAPHS_DIR="${EXPERIMENT_METRICS_DIR}/graphs"
  mkdir -p "${EXPERIMENT_RESULTS_DIR}" "${EXPERIMENT_METRICS_PROM_DIR}" "${EXPERIMENT_GRAPHS_DIR}"

  if [[ ! -f "${EXPERIMENT_DIR}/README.md" ]]; then
    cat > "${EXPERIMENT_DIR}/README.md" <<EOF
# ${LANE} run

- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Benchmark artifacts: ./results/
- Metrics artifacts: ./metrics/
- Topology artifacts: ./results/topology.txt and ./topology-metadata.json
- Graph artifacts: ./metrics/graphs/
- Run mode: results-only by default (validation/startup capture can be re-enabled)
EOF
  fi

  printf '%s' "${EXPERIMENT_DIR}"
}

record_experiment_metadata() {
  local dir
  dir="$(ensure_experiment_dir)"

  local profile
  local tfvars
  local model_source
  local model_served
  local tp
  local pp
  local dp
  local max_model_len
  local gpu_mem
  local network_peak_bandwidth_gbps
  local engine_name
  local task_suite
  local aws_profile
  local aws_region
  local run_id
  local cluster_nodes_json

  profile="${EKS_INFERENCE_CONFIG}"
  tfvars="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"
  model_source="$(config_value model.source)"
  model_served="$(config_value model.served_name)"
  tp="$(config_value engine.tensor_parallel_size)"
  pp="$(config_value engine.pipeline_parallel_size)"
  dp="$(config_value engine.data_parallel_size)"
  max_model_len="$(config_value engine.max_model_len)"
  gpu_mem="$(config_value engine.gpu_memory_utilization)"
  network_peak_bandwidth_gbps="$(config_value runtime.network_peak_bandwidth_gbps 2>/dev/null || printf '0')"
  engine_name="$(config_value engine.name)"
  task_suite="${TASK_SUITE:-0}"
  aws_profile="${AWS_PROFILE:-}"
  aws_region="${AWS_REGION:-}"
  run_id="$(basename "${dir}")"
  cluster_nodes_json="$((kubectl get nodes -o json 2>/dev/null || printf '%s' '{}') | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    print("[]")
    raise SystemExit(0)
items = []
for node in payload.get("items", []):
    meta = node.get("metadata", {})
    labels = meta.get("labels", {})
    provider = node.get("spec", {}).get("providerID", "")
    instance_id = provider.rsplit("/", 1)[-1] if provider else ""
    items.append({
        "name": meta.get("name", ""),
        "instance_type": labels.get("node.kubernetes.io/instance-type", ""),
        "ec2_instance_id": instance_id,
        "provider_id": provider,
        "workload": labels.get("workload", ""),
        "accelerator": labels.get("accelerator", ""),
        "zone": labels.get("topology.kubernetes.io/zone", ""),
    })
print(json.dumps(items))
')"

  cat > "${dir}/run-metadata.json" <<EOF
{
  "lane": "${LANE}",
  "experiment_dir": "${dir}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "inference_profile": "${profile}",
  "tfvars_file": "${tfvars}",
  "engine": "${engine_name}",
  "model_source": "${model_source}",
  "served_model_name": "${model_served}",
  "tensor_parallel_size": ${tp:-0},
  "pipeline_parallel_size": ${pp:-0},
  "data_parallel_size": ${dp:-0},
  "max_model_len": ${max_model_len:-0},
  "gpu_memory_utilization": ${gpu_mem:-0.0},
  "network_peak_bandwidth_gbps": ${network_peak_bandwidth_gbps:-0},
  "aws_profile": "${aws_profile}",
  "aws_region": "${aws_region}",
  "cluster_nodes": ${cluster_nodes_json:-[]}
}
EOF

  local run_readme
  run_readme="${dir}/README.md"
  if [[ ! -f "${run_readme}" ]]; then
    cat > "${run_readme}" <<EOF
# ${LANE} run — ${run_id}

## Artifacts

- Results: ./results/
- Metrics: ./metrics/
- Benchmark JSON: ./results/benchmark-*.json
- Startup latency: ./results/startup-latency.json
- Topology snapshot: ./results/topology.txt
- Topology metadata: ./topology-metadata.json
- Graphs: ./metrics/graphs/

Default `run-lane` mode skips validation and startup latency so repeated benchmarks only capture results.

## Notes

Auto-generated run scaffold. Fill in findings after execution.
EOF
  fi
}

record_scenario_metadata() {
  local dir
  dir="$(ensure_experiment_dir)"

  local model_source
  local model_served
  local tp
  local pp
  local dp
  local max_model_len
  local run_id

  model_source="$(config_value model.source)"
  model_served="$(config_value model.served_name)"
  tp="$(config_value engine.tensor_parallel_size)"
  pp="$(config_value engine.pipeline_parallel_size)"
  dp="$(config_value engine.data_parallel_size)"
  max_model_len="$(config_value engine.max_model_len)"
  run_id="$(basename "${dir}")"

  cat > "${dir}/scenario-metadata.json" <<EOF
{
  "run_id": "${run_id}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lane": "${LANE}",
  "task_suite": ${TASK_SUITE:-0},
  "tfvars_file": "${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}",
  "inference_profile": "${EKS_INFERENCE_CONFIG}",
  "model_source": "${model_source}",
  "served_model_name": "${model_served}",
  "parallelism": {
    "tensor_parallel_size": ${tp:-0},
    "pipeline_parallel_size": ${pp:-0},
    "data_parallel_size": ${dp:-0}
  },
  "max_model_len": ${max_model_len:-0},
  "aws": {
    "profile": "${AWS_PROFILE:-}",
    "region": "${AWS_REGION:-}"
  }
}
EOF
}

capture_cluster_snapshot() {
  local dir
  dir="$(ensure_experiment_dir)"
  kubectl -n "${NAMESPACE:-inference-engine}" get pods -o wide > "${dir}/pods.txt" || true
  kubectl -n "${NAMESPACE:-inference-engine}" get svc > "${dir}/services.txt" || true
  kubectl -n monitoring get pods > "${dir}/monitoring-pods.txt" || true
}

require_supported_lane() {
  case "${LANE}" in
    ray-vllm|k8s-vllm|dynamo-vllm|dynamo-sglang|dynamo-trtllm)
      ;;
    *)
      echo "Unsupported LANE=${LANE}. Supported lanes: ray-vllm, k8s-vllm, dynamo-vllm, dynamo-sglang, dynamo-trtllm." >&2
      exit 1
      ;;
  esac
}

lane_is_future() {
  case "${LANE}" in
    dynamo-sglang|dynamo-trtllm)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

fail_lane_not_implemented() {
  echo "LANE=${LANE} is planned but not implemented yet in this repo." >&2
  echo "See .eks/dynamo/README.md and docs/eks_experiment_matrix.md for the intended structure and rollout plan." >&2
  exit 1
}
