# EKS Inference Proposal — Quick Review

## Quick summary

Stand up an AWS EKS environment that lets the team test:

1. **current GPU-based vLLM deployment flow** on managed Kubernetes
2. **future multi-node sharded inference** for a single model

This is intentionally a testbed, not a final production platform.

## Cluster shape

- **1 x system node**: `t3.large`
- **2 x inference nodes**: `g5.xlarge` by default
- region selected by preflight (`g5` first, `g6` fallback where appropriate)

## What is included

- Terraform stack under `terraform/stacks/eks-inference`
- reusable module under `terraform/modules/eks-inference`
- AWS preflight checks
- EKS vLLM path for current repo shape
- KubeRay path for future sharded multi-node testing

## Key choices

### Is Ray required?

No. vLLM supports multi-node sharding with or without Ray.

We chose **Ray/KubeRay** for the EKS path because it is easier to operate on Kubernetes than coordinating manual multi-node startup.

## Recommended review order

1. `docs/eks_terraform_quick_review.md`
2. `terraform/stacks/eks-inference/README.md`
3. `terraform/modules/eks-inference/main.tf`
4. `.kube/eks/ray/ray-vllm-service.yaml`

## Minimal commands worth knowing

```bash
scripts/eks/preflight.sh
scripts/eks/up-vllm.sh
scripts/eks/up-ray-vllm.sh
```
