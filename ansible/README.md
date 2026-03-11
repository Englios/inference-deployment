# Ansible orchestration for EKS experiments

This directory is the canonical operator interface for EKS experiment workflows in this repo.

## Design intent

- Terraform remains the infra provisioning tool.
- Kubernetes/Helm/operators remain the runtime control plane.
- Shell scripts remain internal backend implementation details.
- Ansible is the supported workflow and composition layer.

This keeps the current repo stable while making experiment runs easier to read, review, and extend.

## Layout

- `inventory/hosts.yml` — local control host inventory
- `group_vars/all.yml` — shared defaults for lane runs
- `playbooks/cluster.yml` — cluster lifecycle steps
- `playbooks/monitoring.yml` — monitoring lifecycle steps
- `playbooks/lane_up.yml` — lane bring-up
- `playbooks/lane_validate.yml` — lane validation
- `playbooks/lane_benchmark.yml` — lane benchmark
- `playbooks/experiment.yml` — end-to-end workflow wrapper
- `playbooks/infra_apply.yml` — plan/apply/kubeconfig only
- `playbooks/monitoring_refresh.yml` — install + validate monitoring only
- `playbooks/lane_deploy.yml` — deploy selected lane only
- `playbooks/lane_run.yml` — run validate/benchmark/capture only
- `playbooks/cleanup_namespace.yml` — clear inference-engine resources
- `playbooks/destroy_infra.yml` — destroy Terraform-managed EKS infrastructure
- `playbooks/context_sweep.yml` — run shared-profile context sweep experiments
- `playbooks/orchestrate_experiment.yml` — full lifecycle with toggles

## Typical usage

```bash
export HF_TOKEN=...
export AWS_PROFILE=dpro-gpu-test
export AWS_REGION=us-west-2
export AWS_DEFAULT_OUTPUT=json
export VLLM_API_KEY=...
export TFVARS_FILE="$PWD/terraform/stacks/eks-inference/terraform.g7e-2x2.tfvars"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/experiment.yml \
  -e lane=ray-vllm \
  -e task_suite=1
```

## Supported phase-based commands

```bash
# 1) Infra only
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$PWD/terraform/stacks/eks-inference/terraform.g7e-2x2.tfvars"

# 2) Monitoring only
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/monitoring_refresh.yml \
  -e repo_root="$PWD"

# 3) Deploy lane only
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_deploy.yml \
  -e repo_root="$PWD" -e lane=ray-vllm

# 4) Run benchmark + captures only
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_run.yml \
  -e repo_root="$PWD" -e lane=ray-vllm -e task_suite=1

# 5) Full orchestrated lifecycle (toggle infra/monitoring/cleanup)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/orchestrate_experiment.yml \
  -e repo_root="$PWD" \
  -e lane=ray-vllm \
  -e task_suite=1 \
  -e run_infra=false \
  -e run_monitoring=true \
  -e run_cleanup=true

# 6) Destroy infra when you're done spending money
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/destroy_infra.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$PWD/terraform/stacks/eks-inference/terraform.g7e-2x2.tfvars"

# 7) Sweep context sizes through the shared profile path
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/context_sweep.yml \
  -e repo_root="$PWD" \
  -e context_windows="32768 65536 131072"
```

Optional experiment controls:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/experiment.yml \
  -e lane=dynamo-vllm \
  -e task_suite=1 \
  -e experiment_timestamp="2026-03-11T21-30-00" \
  -e experiment_dir="/tmp/exp-dynamo-vllm"
```

The lane run workflow automatically captures:

- run metadata (`run-metadata.json`)
- run scaffold (`README.md`)
- topology metadata (`topology-metadata.json` with node/GPU counts)
- benchmark JSON/meta files
- topology snapshots
- observed GPU and Prometheus target/rules snapshots
- benchmark-window time-series metric exports (`metrics/token-metrics.json`, `metrics/network-metrics.json`, `metrics/gpu-metrics.json`)
- auto-rendered benchmarking plots (`metrics/graphs/*.png`)
- human-readable Prometheus summary (`metrics/prometheus/summary.md`)

`lane_run.yml` defaults to a results-only benchmark pass: it skips validation and startup latency unless you explicitly set `-e skip_validate=false -e skip_startup_latency=false`.
It also defaults to a light stress shape of `benchmark_rounds=2` and `benchmark_concurrency=2`, which you can raise per run.

## Supported lanes today

- `ray-vllm`
- `k8s-vllm`
- `dynamo-vllm`

Planned lanes are documented in `.eks/dynamo/README.md` and `docs/eks_experiment_matrix.md`.

## Interface policy

- Use Ansible playbooks for operator workflows.
- Treat `scripts/eks/*.sh` as internal implementation details.
- Update docs and runbooks to point at `ansible/playbooks/*.yml`, not raw shell scripts.
