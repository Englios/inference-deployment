# EKS Inference Proposal — Quick Review

## Quick summary

Stand up an AWS EKS environment that lets the team test:

1. **multi-node sharded inference** for a single large model

This is intentionally a testbed, not a final production platform.

## Cluster shape

- **1 x system node**: `t3.large`
- **2 x inference nodes**: `g7e.12xlarge`
- region selected by preflight with `g7e` first and `g6e` fallback where needed
- inter-node network target on G7e: **400 Gbps with EFA support**

## What is included

- Terraform stack under `terraform/stacks/eks-inference`
- reusable module under `terraform/modules/eks-inference`
- AWS preflight checks
- KubeRay path for the primary **TP=2 + PP=2** multi-node sharded test
- benchmark helpers for TTFT, generation speed, and GPU usage
- Prometheus/Grafana + DCGM monitoring for metrics capture

## Key choices

### Is Ray required?

No. vLLM supports multi-node sharding with or without Ray.

We chose **Ray/KubeRay** as the primary Option 3 path because the goal is now explicit **cross-node TP+PP sharding** for one model across 4 GPUs.

The current mapping is:

- **Option 3 (primary):** 2 nodes × 2 GPUs, using **TP=2 + PP=2** with `Qwen/Qwen3.5-122B-A10B`


## Recommended review order

1. `docs/eks_terraform_quick_review.md`
2. `terraform/stacks/eks-inference/README.md`
3. `terraform/modules/eks-inference/main.tf`
4. `.eks/ray/ray-vllm-service.yaml`

## Minimal commands worth knowing

```bash
scripts/eks/preflight.sh
scripts/eks/up-ray-vllm.sh
scripts/eks/benchmark-ray-vllm.sh
scripts/eks/collect-gpu-metrics.sh
```
