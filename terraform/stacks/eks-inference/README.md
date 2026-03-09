# EKS Inference Cluster Terraform Stack

This stack provisions an Amazon EKS cluster for inference testing with a small untained system node group and a fixed GPU inference node group.

## Quick review first

1. `docs/eks_terraform_quick_review.md`
2. `terraform/modules/eks-inference/main.tf`
3. `.kube/eks/ray/ray-vllm-service.yaml`
4. `.kube/eks/vllm-option2/deployment.yaml`

## Default topology in this repo now

The repo is now tuned for **Option 3 first**:

- **2 inference nodes**
- each node uses `g7e.12xlarge`
- the distributed Ray path shards **one `Qwen/Qwen3.5-122B-A10B` model across 4 GPUs total**
- the default Ray configuration uses **4 GPU workers** with `tensor_parallel_size=2` and `pipeline_parallel_size=2`

That means the intended Option 3 experiment is now the **single sharded 4-GPU model path across 2 nodes**, using:

- **TP=2** inside each 2-GPU node
- **PP=2** across the two nodes
- a heavier **122B-A10B MoE stress profile**

When you want to try **Option 2 later**, switch Terraform to:

```hcl
gpu_node_instance_types = ["g7e.24xlarge"]
node_group_size         = 1
```

and then re-tune the workload so the 4-GPU shard lives on one node instead of across two nodes. In that later case, you would switch to the checked-in **Option 2 overlay** under `.kube/eks/vllm-option2/`, which also uses **TP=4 / PP=1** but on one node.

## Important model note

For the primary Ray Option 3 path, use the official MoE checkpoint:

```text
Qwen/Qwen3.5-122B-A10B
```

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

That does make **Ray/KubeRay** the more appropriate primary path in this repo.

So the repo now treats the paths like this:

- **Primary Option 3 path:** Ray/KubeRay across 2 nodes for one sharded `Qwen/Qwen3.5-122B-A10B` model using **TP=2 + PP=2**
- **Option 2 later path:** single-node 4-GPU overlay under `.kube/eks/vllm-option2/` with **TP=4 + PP=1**
- **MoE-friendly fallback path:** `.kube/eks/ray/ray-vllm-122b-a10b.yaml` using **TP=4 + PP=1**
- **Plain non-Ray path:** kept only as a simpler sanity / fallback path

## The only commands that matter at a glance

- `scripts/eks/preflight.sh`
- `scripts/eks/up-ray-vllm.sh`
- `scripts/eks/benchmark-vllm.sh`
- `scripts/eks/benchmark-ray-vllm.sh`
- `scripts/eks/collect-gpu-metrics.sh`
- `scripts/eks/destroy.sh`

## AWS prerequisites

- AWS account with quota for `g7e.12xlarge` in your chosen region
- An IAM principal with permissions for VPC, EKS, EC2, IAM, and EBS CSI addon creation
- AWS CLI configured locally
- `kubectl`, `helm`, and either `terraform` or `docker`

Before any Terraform apply, `scripts/eks/up*.sh` runs `scripts/eks/preflight.sh` to verify credentials, region enablement, EKS reachability, and whether the requested GPU instance type is offered.

## Minimal deploy sequence on AWS

```bash
cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
$EDITOR terraform/stacks/eks-inference/terraform.tfvars

export AWS_PROFILE=your-profile
export AWS_REGION=us-west-2
export HF_TOKEN="hf_xxx"
export VLLM_API_KEY="supersecretkey"

scripts/eks/preflight.sh
scripts/eks/up-ray-vllm.sh
```

## Where to put secrets

For the EKS scripts in this repo, the intended pattern is:

- keep secrets **in your local shell environment**
- let the deploy scripts create/update Kubernetes Secrets from those env vars

The main values are:

```bash
export HF_TOKEN="hf_xxx"
export VLLM_API_KEY="supersecretkey"
```

Then:

- `scripts/eks/deploy-vllm.sh` creates `vllm-secrets`
- `scripts/eks/deploy-ray-vllm.sh` creates `ray-vllm-secrets`

Do **not** commit real secrets into the repo. The `.gitignore` already ignores common `secrets*` files.

## Overlays in this repo

- **Option 3 primary path:** `.kube/eks/ray/ray-vllm-service.yaml` using **122B-A10B** with **TP=2 + PP=2** across 2 nodes
- **Option 2 later path:** `.kube/eks/vllm-option2/` using **TP=4 + PP=1** on 1 node
- **122B MoE-friendly fallback path:** `.kube/eks/ray/ray-vllm-122b-a10b.yaml` using **TP=4 + PP=1** across 4 GPUs total
- **Plain non-Ray sanity path:** `.kube/eks/vllm/`

## Regional fallback

If `g7e` is unavailable in your target region, use a `g6e.*` fallback in `terraform.tfvars`.

## Day-2 operations: scale down or remove later

### Stop only the workloads

```bash
kubectl -n inference-engine delete statefulset vllm-server
kubectl -n inference-engine delete rayservice ray-vllm
```

### Shrink the cluster

Edit `terraform/stacks/eks-inference/terraform.tfvars` and reduce the node counts, then apply again:

```bash
scripts/eks/plan.sh
scripts/eks/apply.sh
```

### Remove everything

```bash
scripts/eks/destroy.sh
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
scripts/eks/benchmark-ray-vllm.sh
scripts/eks/collect-gpu-metrics.sh
```

To compare context-window settings directly:

```bash
export VLLM_API_KEY="supersecretkey"
scripts/eks/context-sweep.sh
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
- the primary Ray path uses `Qwen/Qwen3.5-122B-A10B` across 4 total GPUs with `tensor_parallel_size=2` and `pipeline_parallel_size=2`
- the Option 2 overlay uses `Qwen/Qwen3.5-27B` on one `g7e.24xlarge`-class node with `tensor_parallel_size=4` and `pipeline_parallel_size=1`
- Ray head and operators are intended to run on the separate system node

## Lighter baseline / comparison model

The repo also keeps a lighter dense comparison model around:

- `Qwen/Qwen3.5-27B`

That is useful when you want a simpler, cleaner baseline after the heavier 122B infra stress test.

If you later want a cleaner model-to-model baseline, use the plain non-Ray path or the Option 2 overlay with `Qwen/Qwen3.5-27B`.

If the primary TP+PP path is unstable for this MoE model, use the checked-in fallback manifest:

```bash
export RAY_MANIFEST="${PWD}/.kube/eks/ray/ray-vllm-122b-a10b.yaml"
export RAY_SERVICE_NAME="ray-vllm-122b-a10b-tp4"

scripts/eks/deploy-ray-vllm.sh
scripts/eks/validate-ray-vllm.sh
scripts/eks/benchmark-ray-vllm.sh
```

Important clarification:

- **TP=4 / PP=1 still uses 4 GPUs total**, not 5
- it simply puts all 4 GPUs into one tensor-parallel group
- that means it can still run on **2 nodes × 2 GPUs**, but it no longer preserves the “2 GPUs per node as separate pipeline stages” structure

So for your stated hardware intent:

- **TP=2 / PP=2** = topology-aligned default
- **TP=4 / PP=1** = same 4 GPUs, but topology-flatter fallback

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
