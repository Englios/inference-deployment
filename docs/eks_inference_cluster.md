# EKS Inference Cluster Notes

This repo now includes a Terraform stack for provisioning an AWS EKS cluster aimed at short-lived distributed inference experiments.

## Summary

- Stack path: `terraform/stacks/eks-inference`
- Reusable module path: `terraform/modules/eks-inference`
- Helper scripts: `scripts/eks/`
- Default system node shape: `t3.large`
- Default inference node shape: `g7e.12xlarge`
- Default inference node count: `2`

## Typical flow

```bash
cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
scripts/eks/preflight.sh
scripts/eks/up-ray-vllm.sh
```

These scripts are convenience wrappers around standard Terraform and Kubernetes commands.

## Current target topology

The repo is now tuned for **Option 3 first**:

- 2 inference nodes
- each node shaped like `g7e.12xlarge`
- one model sharded across **4 total GPUs**
- Ray-backed execution with **tensor_parallel_size=2** and **pipeline_parallel_size=2**
- model: `Qwen/Qwen3.5-122B-A10B`
- inter-node network class on G7e: **400 Gbps with EFA support**

If you later want **Option 2**, switch the Terraform node shape to `g7e.24xlarge`, set the node count to `1`, and keep the model sharded across the 4 GPUs on that single node.

## Why Ray is the default now

Your current target is no longer just “multi-node exists”; it is:

- one model
- sharded across 4 GPUs
- over 2 nodes
- as a heavier infra stress profile

That makes the Ray/KubeRay path the more natural default for the main experiment in this repo.

The plain non-Ray path is still kept around as a simpler fallback / sanity path, but the intended Option 3 experiment is now the Ray path.

If TP+PP proves unstable for the MoE model, the repo also includes a fallback Ray manifest that uses **TP=4 / PP=1** instead:

- `.kube/eks/ray/ray-vllm-122b-a10b.yaml`

## Scale down or remove later

You have three practical options after testing:

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

That is the full Terraform teardown path for the EKS stack.

## Model choice

For this topology-matched EKS path, the repo now uses:

- **Primary model:** `Qwen/Qwen3.5-122B-A10B`
- **Runtime:** vLLM
- **Reasoning parser:** `qwen3`

We are not using `unsloth/Qwen3.5-27B-GGUF` here because GGUF is a better fit for llama.cpp-style runtimes than for the vLLM GPU path used in this repo.

The lighter dense comparison model kept in the repo is:

- `Qwen/Qwen3.5-27B`

## Why 122B-A10B is the primary stress profile now

`Qwen/Qwen3.5-122B-A10B` is an **MoE** model and a heavier infra target for this 4 × 96GB setup.

If your main question is **"how will the infra hold up?"** rather than **"which model is better?"**, this is a reasonable primary stress profile.

The primary path keeps your original topology-first intent by using **TP=2 + PP=2**.
The fallback path uses **TP=4 + PP=1** if you want the simpler MoE-friendly layout later.

Why `TP=4 / PP=1` is called “MoE-friendly” here:

- it keeps all 4 GPUs in one tensor-parallel group
- it avoids adding pipeline-stage orchestration on top of MoE routing behavior
- it is a cleaner fallback if the first failures are coming from PP coordination rather than raw model fit

Important clarification:

- **TP=4 / PP=1 does not require 5 GPUs**
- it still uses the same **4 GPUs total**
- it just uses them as one 4-way TP group instead of two 2-GPU TP stages connected by PP

So if you want to respect the physical shape of **2 GPUs per node × 2 nodes**, the repo's primary path remains **TP=2 / PP=2**.

## Performance checks to run later

Once the service is up, use:

```bash
scripts/eks/benchmark-ray-vllm.sh
scripts/eks/collect-gpu-metrics.sh
```

To compare multiple context-window settings with the same benchmark prompt:

```bash
scripts/eks/context-sweep.sh
```

These scripts are intended to report:

- **TTFT**
- **generation tokens/sec**
- **total request latency**
- **GPU utilization and memory per worker**
- **worker placement by node**

Important metric nuance:

- **TTFT** and **generation speed** are directly measurable
- **system-level throughput** is directly measurable from benchmark traffic
- **per-node throughput** is an approximation unless you benchmark nodes independently
- **per-GPU token contribution** is only an estimate in TP/PP serving, not a precise ground-truth metric reported by vLLM

## Context length vs sequence count

Yes — these are different knobs.

- **Context length** = how many tokens a single request can keep in its working window
- **Sequence count** = how many active requests/sequences the engine schedules at once

In this repo's configs:

- `VLLM_MAX_MODEL_LEN` controls the **context window**
- `VLLM_MAX_NUM_SEQS` controls **scheduler concurrency**

They interact through KV-cache usage, but they are not the same parameter.

## What about users sending arbitrarily long inputs?

Yes, users can send variable-length inputs.

But the serving stack does **not** automatically do semantic chunking just because input size varies.

The correct mental model is:

- **vLLM / model server**: enforces the context window
- **application layer / middleware**: decides what to do when input is too long

Common strategies:

- reject with a friendly limit message
- truncate
- summarize older context
- retrieve and chunk only the relevant context

So dynamic input length is normal, but **dynamic chunking is an application decision**, not something to assume from the model server.
