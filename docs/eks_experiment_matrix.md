# EKS experiment matrix

This document defines the repo shape for repeatable EKS inference experiments across multiple runtime lanes.

## Goals

- keep infrastructure comparisons fair across lanes
- reuse the same validation and benchmark contract where possible
- let the repo compare current and future production candidates without rewriting the experiment workflow each time

## Lane names

- `ray-vllm` — current distributed EKS baseline using KubeRay + RayService
- `k8s-vllm` — plain Kubernetes vLLM baseline
- `dynamo-vllm` — future Dynamo vLLM lane
- `dynamo-sglang` — future Dynamo SGLang lane
- `dynamo-trtllm` — future Dynamo TensorRT-LLM lane

## Shared infrastructure flow

All lanes should reuse the same cluster and monitoring lifecycle:

```bash
export TFVARS_FILE="$PWD/terraform/stacks/eks-inference/<profile>.tfvars"
export HF_TOKEN=...

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$TFVARS_FILE"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/monitoring_refresh.yml \
  -e repo_root="$PWD"
```

For `ray-vllm` and `dynamo-vllm`, model/runtime settings now come from one shared config:

```text
.eks/inference-profile.json
```

This single profile controls lane-shared knobs such as:

- model id / source / served name
- tensor / pipeline / data parallel sizing
- max model length
- GPU memory utilization
- runtime image/version knobs
- Ray cluster sizing
- Dynamo frontend/worker sizing

Then run lane-specific setup via the Ansible wrapper:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_deploy.yml \
  -e repo_root="$PWD" -e lane=ray-vllm

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_validate.yml \
  -e repo_root="$PWD" -e lane=ray-vllm

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_benchmark.yml \
  -e repo_root="$PWD" -e lane=ray-vllm -e task_suite=1
```

Or use the combined runner that benchmarks and captures topology/artifacts from an already-live lane:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_run.yml \
  -e repo_root="$PWD" -e lane=ray-vllm -e task_suite=1
```

## Canonical playbooks

The repo provides these lane-aware operator entrypoints:

- `ansible/playbooks/lane_deploy.yml`
- `ansible/playbooks/lane_validate.yml`
- `ansible/playbooks/lane_benchmark.yml`
- `ansible/playbooks/lane_run.yml`
- `ansible/playbooks/orchestrate_experiment.yml`

These playbooks dispatch to the current concrete backend for implemented lanes and fail clearly for planned lanes.

The implemented shared-config render flow is:

```bash
python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane ray-vllm --output-root .eks/rendered
python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane dynamo-vllm --output-root .eks/rendered
```

The deploy scripts run this automatically before applying manifests.

## Automatic experiment capture

Lane workflows now auto-create an experiment run directory and capture core artifacts.

- default run directory: `experiments/<lane>/runs/<YYYY-MM>/run-<timestamp>/`
- override timestamp: `EXPERIMENT_TIMESTAMP=...`
- override output dir: `EXPERIMENT_DIR=/custom/path`

Captured artifacts include:

- `run-metadata.json` (lane/profile/model/parallelism snapshot)
- `scenario-metadata.json` (standardized run scenario descriptor)
- run scaffold (`README.md`)
- live-state snapshots (`metrics/observed-pods.txt`, `metrics/observed-services.txt`, `metrics/observed-monitoring-pods.txt`)
- benchmark JSON output (`results/benchmark-*.json`)
- benchmark metadata (`results/benchmark-*.meta`)
- startup latency snapshot from the lane run workflow when explicitly enabled:
  - `results/startup-latency.json` (`/health` and `/v1/models` readiness times)
- topology snapshot (`results/topology.txt`)
- topology metadata (`topology-metadata.json`) including:
  - `cluster_gpu_node_count`
  - `cluster_gpu_allocatable_total`
  - `lane_worker_pod_count`
  - `lane_worker_node_count`
  - `lane_worker_gpu_limit_total`
- observed metrics snapshots from the lane run workflow:
  - `metrics/observed-gpu-nvidia-smi.txt`
  - `metrics/observed-nodes.json`
  - `metrics/observed-k8s-version.txt`
  - `metrics/prometheus/observed-prometheus-targets.json`
  - `metrics/prometheus/observed-prometheus-rules.json`
  - lane-specific observed pod snapshots (Ray or Dynamo)
- token metrics snapshot from the lane run workflow:
  - `metrics/token-metrics.json` (benchmark-window time series for ongoing requests, queue depth, and Ray Serve request rates)
- GPU metrics snapshot from the lane run workflow:
  - `metrics/gpu-metrics.json` (benchmark-window time series for DCGM GPU util, memory, power, and temperature)
- network metrics snapshot from the lane run workflow:
  - `metrics/network-metrics.json` (benchmark-window time series for pod+node throughput and packet drop rates)
- rendered graph exports (`scripts/eks/render-experiment-graphs.py`):
  - `metrics/graphs/benchmark-summary.png`
  - `metrics/graphs/gpu-metrics.png`
  - `metrics/graphs/token-metrics.png`
  - `metrics/graphs/network-metrics.png`
  - `metrics/prometheus/summary.md`

## Ansible orchestration layer

The repo also provides an Ansible wrapper under `ansible/` for readability and workflow composition.

- Ansible is the orchestration layer.
- Existing shell scripts remain the execution backend.
- Terraform remains the infra tool.
- Kubernetes/Helm/operators remain the runtime control plane.

Typical usage:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/experiment.yml \
  -e lane=ray-vllm \
  -e task_suite=1
```

This keeps operational logic readable while the shell scripts remain backend primitives only.

## Metrics contract

Every lane should capture the same core scorecard.

### Serving metrics

- TTFT
- generation tokens/second
- total tokens/second
- prompt/completion token counts
- request queue depth
- KV cache usage

### GPU metrics

- GPU utilization
- framebuffer usage
- power draw
- temperature
- PCIe or interconnect throughput when available
- energy counters when exposed

### Host metrics

- CPU
- RAM
- disk
- network

### Stability metrics

- time to healthy
- pod restart count
- operator/controller errors for operator-backed lanes
- XID or driver error events when log collection exists

## Comparison rules

To keep experiments fair:

1. Use the same `TFVARS_FILE` profile for every lane in a comparison set.
2. Change one variable family at a time:
   - infra shape
   - runtime/orchestrator lane
   - engine knobs
3. Use the same prompt/task suite and benchmark window.
4. Validate when bringing up or changing the lane; skip it for repeated benchmark-only runs.
5. Capture the same metrics set for all lanes in the comparison.

## Directory layout

### Active assets

- `.eks/ray/` — active Ray/KubeRay deployment assets
- `.eks/monitoring/` — Prometheus/Grafana/DCGM assets
- `.eks/dynamo/` — Dynamo lane assets and notes

### Local or generic manifests

- `.kube/vllm/`
- `.kube/sglang/`
- `.kube/llamacpp/`
- `.kube/middleware/`

## Experiments directory convention

Use lane-oriented experiment identifiers:

- `eks-ray-vllm-<model>-<shape>`
- `eks-k8s-vllm-<model>-<shape>`
- `eks-dynamo-vllm-<model>-<shape>`
- `eks-dynamo-sglang-<model>-<shape>`

Each run should record:

- lane name
- infra profile (`TFVARS_FILE` source)
- model and engine
- exact deployment knobs
- validation commands used
- benchmark command used
- metrics capture status
- findings and decision notes

## Recommended run order

For a new model or infra profile, run in this order:

1. `ray-vllm`
2. `k8s-vllm`
3. `dynamo-vllm`
4. `dynamo-sglang`
5. `dynamo-trtllm` (later or only when justified)

This preserves continuity with the current baseline while moving toward production-candidate lanes.

## Planned repo additions for richer experiments

- generalized GPU metrics collection that is not Ray-label specific
- XID error log capture into Loki
- lane-specific Prometheus dashboards and summary templates
- Dynamo deploy/validate/benchmark wrappers matching the lane contract

## Current Dynamo manifest baseline

The repo now carries a first Dynamo-oriented baseline for future implementation work through:

- `.eks/inference-profile.json`
- `.eks/dynamo/hf-token-secret.example.yaml`
- `.eks/dynamo/namespace.yaml.tpl`
- `.eks/dynamo/model-cache-pvc.yaml.tpl`
- `.eks/dynamo/vllm/agg.yaml.tpl`
- `.eks/dynamo/service-llm.yaml.tpl`
- `.eks/monitoring/dynamo-frontend-podmonitor.yaml.tpl`
- `.eks/monitoring/dynamo-worker-podmonitor.yaml.tpl`
- `.eks/monitoring/dynamo-llm-servicemonitor.yaml.tpl`

Rendered apply targets are generated under `.eks/rendered/` and ignored by git.

When updating shared lane knobs, change `.eks/inference-profile.json` first, then rerender.
