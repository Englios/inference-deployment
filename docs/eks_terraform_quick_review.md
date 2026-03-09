# EKS Inference Proposal — Quick Review

## Quick summary

Stand up an AWS EKS environment that lets the team test:

1. **multi-node sharded inference** for a single `Qwen/Qwen3.5-122B-A10B` model
2. a later comparison against a **single-node 4-GPU** variant of the same model

This is intentionally a testbed, not a final production platform.

## Cluster shape

- **1 x system node**: `t3.large`
- **2 x inference nodes**: `g7e.12xlarge` by default for Option 3
- later Option 2 target: **1 x `g7e.24xlarge`**
- region selected by preflight with `g7e` first and `g6e` fallback where needed
- inter-node network target on G7e: **400 Gbps with EFA support**

## What is included

- Terraform stack under `terraform/stacks/eks-inference`
- reusable module under `terraform/modules/eks-inference`
- AWS preflight checks
- plain EKS vLLM path for simpler sanity checks
- KubeRay path for the primary **TP=2 + PP=2** multi-node sharded test
- TP=4 / PP=1 fallback path for the same 122B MoE model
- benchmark helpers for TTFT, generation speed, and GPU usage

## Key choices

### Is Ray required?

No. vLLM supports multi-node sharding with or without Ray.

We chose **Ray/KubeRay** as the primary Option 3 path because the goal is now explicit **cross-node TP+PP sharding** for one model across 4 GPUs.

The current mapping is:

- **Option 3 (primary):** 2 nodes × 2 GPUs, using **TP=2 + PP=2** with `Qwen/Qwen3.5-122B-A10B`
- **Option 2 (later comparison):** 1 node × 4 GPUs, likely using **TP=4 + PP=1**

There is also a checked-in fallback 122B manifest that uses **TP=4 + PP=1** if the TP+PP MoE path is unstable.

Why that fallback exists:

- `Qwen/Qwen3.5-122B-A10B` is an **MoE** model
- `TP=4 / PP=1` is the simpler “all 4 GPUs in one tensor-parallel group” layout
- it is easier to reason about if PP-specific orchestration becomes the source of failures

## Recommended review order

1. `docs/eks_terraform_quick_review.md`
2. `terraform/stacks/eks-inference/README.md`
3. `terraform/modules/eks-inference/main.tf`
4. `.kube/eks/ray/ray-vllm-service.yaml`
5. `.kube/eks/vllm-option2/deployment.yaml`

## Minimal commands worth knowing

```bash
scripts/eks/preflight.sh
scripts/eks/up-ray-vllm.sh
scripts/eks/benchmark-ray-vllm.sh
scripts/eks/collect-gpu-metrics.sh
```
