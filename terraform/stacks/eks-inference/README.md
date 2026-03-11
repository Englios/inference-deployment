# EKS Inference Cluster Terraform Stack

This stack provisions an Amazon EKS cluster for inference testing with a small untained system node group and a fixed GPU inference node group.

Repository convention: keep `.eks/` for the current supported deployment manifests only. Experiment-by-experiment parameter changes should live in local `experiments/` notes unless a variant becomes a stable path worth promoting into `.eks/`.

The supported EKS path now includes a lightweight monitoring stack under `.eks/monitoring/` so Prometheus, Grafana, GPU metrics, Ray head metrics, and vLLM serving metrics are available during Ray/vLLM runs.

## Quick review first

1. `docs/eks_terraform_quick_review.md`
2. `terraform/modules/eks-inference/main.tf`
3. `.eks/inference-profile.json`

## Default topology in this repo now

The repo is now tuned for **Option 3 first**:

- **2 inference nodes**
- each node uses `g7e.12xlarge`
- the distributed Ray path shards **one shared-profile model across 4 GPUs total**
- the default Ray configuration uses **4 GPU workers** with `tensor_parallel_size=2` and `pipeline_parallel_size=2`

That means the intended Option 3 experiment is now the **single sharded 4-GPU model path across 2 nodes**, using:

- **TP=2** inside each 2-GPU node
- **PP=2** across the two nodes
- a profile-driven stress configuration

## Important model note

The current checked-in shared profile defaults to:

```text
openai/gpt-oss-120b
```

If you want the heavier Qwen MoE stress test, update `.eks/inference-profile.json` rather than editing manifests by hand.

The lighter dense reference model kept elsewhere in the repo is:

```text
Qwen/Qwen3.5-27B
```

`unsloth/Qwen3.5-27B-GGUF` is a better fit for llama.cpp/GGUF runtimes, not for the vLLM-on-NVIDIA path in this repo.

## Why the default Option 3 path is Ray-based now

Because your actual intended experiment is now explicit:

- one model
- sharded across 4 GPUs total
- over 2 nodes
- as a heavier infra stress profile

That still makes **Ray/KubeRay** the more appropriate primary path in this repo.

So the repo now treats the active path as:

- **Primary path:** Ray/KubeRay across 2 nodes for one shared-profile model using **TP=2 + PP=2**

## The only commands that matter at a glance

- `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml ...`
- `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/monitoring_refresh.yml ...`
- `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_deploy.yml -e lane=ray-vllm ...`
- `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_run.yml -e lane=ray-vllm -e task_suite=1 ...`
- `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/destroy_infra.yml ...`

## AWS prerequisites

- AWS account with quota for `g7e.12xlarge` in your chosen region
- An IAM principal with permissions for VPC, EKS, EC2, IAM, and EBS CSI addon creation
- AWS CLI configured locally
- `kubectl`, `helm`, and either `terraform` or `docker`

Before any Terraform apply, use `ansible/playbooks/infra_apply.yml` so preflight, apply, and kubeconfig refresh stay under the same supported interface.

## Minimal deploy sequence on AWS

```bash
cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
$EDITOR terraform/stacks/eks-inference/terraform.tfvars

export AWS_PROFILE=your-profile
export AWS_REGION=us-west-2
export HF_TOKEN="hf_xxx"
export GRAFANA_ADMIN_PASSWORD="change-me"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$PWD/terraform/stacks/eks-inference/terraform.tfvars"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/monitoring_refresh.yml \
  -e repo_root="$PWD"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_deploy.yml \
  -e repo_root="$PWD" -e lane=ray-vllm
```

## Where to put secrets

For the EKS scripts in this repo, the intended pattern is:

- keep secrets **in your local shell environment**
- let the deploy scripts create/update Kubernetes Secrets from those env vars

The main values are:

```bash
export HF_TOKEN="hf_xxx"
export GRAFANA_ADMIN_PASSWORD="change-me"
```

Then:

- `ansible/playbooks/lane_deploy.yml -e lane=k8s-vllm` creates the vLLM secrets path
- `ansible/playbooks/lane_deploy.yml -e lane=ray-vllm` creates the Ray vLLM secrets path

For the active Ray path in this repo, only `HF_TOKEN` is required by the deployment manifest. `VLLM_API_KEY` is optional and only used by local benchmark helpers if you want to pass a bearer token explicitly.

Do **not** commit real secrets into the repo. The `.gitignore` already ignores common `secrets*` files.

## Overlays in this repo

- **Active path:** `.eks/inference-profile.json` + `.eks/ray/ray-vllm-service.yaml.tpl`, rendered into `.eks/rendered/ray/ray-vllm-service.yaml`

## Regional fallback

If `g7e` is unavailable in your target region, use a `g6e.*` fallback in `terraform.tfvars`.

## Day-2 operations: scale down or remove later

### Stop only the workloads

```bash
kubectl -n inference-engine delete deployment vllm-server
kubectl -n inference-engine delete rayservice ray-vllm
```

### Shrink the cluster

Edit `terraform/stacks/eks-inference/terraform.tfvars` and reduce the node counts, then apply again:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$PWD/terraform/stacks/eks-inference/terraform.tfvars"
```

## Reconfiguring node groups with Terraform

This repo uses **EKS managed node groups** with fixed sizes:

- inference group: `min_size = max_size = desired_size = node_group_size`
- system group: `min_size = max_size = desired_size = system_node_group_size`

So when you change node settings in `terraform/stacks/eks-inference/terraform.tfvars`, the operational effect is usually:

1. run `ansible/playbooks/infra_apply.yml`
2. review whether Terraform will **scale** or **replace** nodes
3. let the playbook apply changes
4. kubeconfig refresh is part of the playbook
5. revalidate the cluster and workloads

If you want to preserve multiple node / EC2 layouts for different experiments, keep multiple local tfvars files under this stack directory and point the wrappers at the one you want with `TFVARS_FILE`.

Example:

```bash
cp terraform/stacks/eks-inference/terraform.tfvars terraform/stacks/eks-inference/terraform.g7e-2x2.tfvars
cp terraform/stacks/eks-inference/terraform.tfvars terraform/stacks/eks-inference/terraform.g7e-1x4.tfvars

export TFVARS_FILE="${PWD}/terraform/stacks/eks-inference/terraform.g7e-1x4.tfvars"
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$TFVARS_FILE"
```

Equivalent supported operator path:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/infra_apply.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$TFVARS_FILE"
```

Supported Ansible workflows honor `TFVARS_FILE`:

- `ansible/playbooks/infra_apply.yml`
- `ansible/playbooks/destroy_infra.yml`

### What kinds of changes do

- `node_group_size` / `system_node_group_size`
  - usually scales the managed node group up or down
- `gpu_node_instance_types` / `system_node_instance_types`
  - typically causes the managed node group to roll or replace nodes to match the new instance type
- disk size changes
  - usually require replacement of affected nodes

### What to expect operationally

- existing pods on changed nodes may be evicted and rescheduled
- Ray head/worker placement may move to different nodes
- if inference nodes are replaced, the Ray/vLLM workload may need to be redeployed or at least revalidated after the node group stabilizes
- monitoring pods should reschedule automatically, but you should still re-check scrape targets afterward

### Safe post-change sequence

After a node-group reconfiguration, use:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/monitoring_refresh.yml \
  -e repo_root="$PWD"

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_validate.yml \
  -e repo_root="$PWD" -e lane=ray-vllm
```

If the Ray workload lost placement or was disrupted during node replacement, re-run:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_deploy.yml \
  -e repo_root="$PWD" -e lane=ray-vllm

ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_validate.yml \
  -e repo_root="$PWD" -e lane=ray-vllm
```

### Remove everything

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/destroy_infra.yml \
  -e repo_root="$PWD" \
  -e tfvars_file="$TFVARS_FILE"
```

## Performance validation later

When the cluster is up, you can benchmark:

- **TTFT**
- **generation tokens/sec**
- **overall response time**
- **per-node GPU usage**
- **GPU memory usage per worker**

with:

```bash
export VLLM_API_KEY="supersecretkey"
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/lane_run.yml \
  -e repo_root="$PWD" -e lane=ray-vllm -e task_suite=1
```

To compare context-window settings directly:

```bash
export VLLM_API_KEY="supersecretkey"
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/context_sweep.yml \
  -e repo_root="$PWD"
```

Notes on the metrics:

- **TTFT** and **generation tokens/sec** are directly measured from the API stream.
- **system-level throughput** is the benchmarked end-to-end output rate.
- **per-node throughput** is best approximated by combining benchmark results with worker placement and GPU utilization.
- **per-GPU token contribution** is only an estimate, not a directly reported vLLM metric, because TP/PP split compute internally rather than attributing exact output tokens to one GPU.

## Context length vs sequence count

These two settings are related, but they are **not the same thing**:

- **Context length** (`VLLM_MAX_MODEL_LEN`) = the maximum token window for a single request
- **Sequence count** (`VLLM_MAX_NUM_SEQS`) = how many active sequences/requests vLLM tries to schedule concurrently

Why it matters:

- increasing **context length** raises per-request KV-cache cost
- increasing **sequence count** raises total concurrent KV-cache cost
- doing both at the same time is what usually pushes a deployment into memory pressure

So your understanding is correct: **sequence length / sequence count is not the same as context length**.

## Resource sizing notes

- `g7e.12xlarge` provides 2 × RTX PRO 6000 96GB GPUs per node
- the primary Ray path uses the shared-profile model across 4 total GPUs with `tensor_parallel_size=2` and `pipeline_parallel_size=2`
- Ray head and operators are intended to run on the separate system node

## Lighter baseline / comparison model

The repo also keeps a lighter dense comparison model around:

- `Qwen/Qwen3.5-27B`

That is useful when you want a simpler, cleaner baseline after the heavier 122B infra stress test.

If you later want model-to-model baselines, add dedicated manifests explicitly for that purpose.

## Handling variable user input lengths

Users can send prompts of many different sizes, but that does **not** mean the serving engine will automatically split long inputs semantically.

Practical rule:

- the model server enforces the configured context window
- if a request is larger than the available window, you need an **upstream policy**

Typical policies are:

- reject with a clear limit error
- truncate input
- summarize/compress previous context
- chunk/retrieve relevant context before sending to the model

So yes, user input length is dynamic — but **semantic chunking should happen above vLLM**, not be assumed inside it.
