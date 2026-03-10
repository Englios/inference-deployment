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

The Ray EKS flow now also installs a lightweight monitoring stack (`kube-prometheus-stack` + `dcgm-exporter`) so future runs retain Prometheus and GPU metrics. Monitoring is split into separate scrape targets for Ray head metrics and the vLLM serving endpoint.

## Current target topology

The repo is tuned for the active Ray multi-node path:

- 2 inference nodes
- each node shaped like `g7e.12xlarge`
- one model sharded across **4 total GPUs**
- Ray-backed execution with **tensor_parallel_size=2** and **pipeline_parallel_size=2**
- model: `Qwen/Qwen3.5-122B-A10B`
- inter-node network class on G7e: **400 Gbps with EFA support**

## Why Ray is the default now

Your current target is no longer just “multi-node exists”; it is:

- one model
- sharded across 4 GPUs
- over 2 nodes
- as a heavier infra stress profile

That makes the Ray/KubeRay path the more natural default for the main experiment in this repo.

The active experiment path in this repo is the Ray path.

## Scale down or remove later

You have three practical options after testing:

### Stop only the workloads

```bash
kubectl -n inference-engine delete deployment vllm-server
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

## Experiment results

The March 2026 experiment established that the EKS + Ray + vLLM infrastructure path worked, `Qwen/Qwen3.5-122B-A10B` failed in the packaged runtime path, and `openai/gpt-oss-120b` served successfully on the same 2-node / 4-GPU topology.

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
