# EKS Inference Cluster Notes

This repo now includes a Terraform stack for provisioning an AWS EKS cluster aimed at short-lived distributed inference experiments.

## Summary

- Stack path: `terraform/stacks/eks-inference`
- Reusable module path: `terraform/modules/eks-inference`
- Helper scripts: `scripts/eks/`
- Default system node shape: `t3.large`
- Default node shape: `g5.xlarge`
- Default node count: `2`

## Typical flow

```bash
cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
scripts/eks/preflight.sh
scripts/eks/up-vllm.sh
```

These scripts are convenience wrappers around standard Terraform and Kubernetes commands.

## Scale down or remove later

You have three practical options after testing:

### Stop only the workloads

```bash
kubectl -n inference-engine delete deploy vllm-server
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

## Recommended model choice

For this cluster shape, the best default is usually the **7B–8B class** rather than the very small 3B class.

- **Recommended single-GPU default:** `Qwen/Qwen2.5-7B-Instruct`
- **Safe fallback for smoke tests:** `Qwen/Qwen2.5-3B-Instruct`
- **Another solid single-GPU option:** `meta-llama/Llama-3.1-8B-Instruct`
- **Recommended bigger dual-node Ray experiment:** `Qwen/Qwen2.5-14B-Instruct`

The EKS vLLM config now defaults to `Qwen/Qwen2.5-7B-Instruct`, and the Ray-based multi-node path now targets `Qwen/Qwen2.5-14B-Instruct`.
