<<<<<<< conflict 1 of 1
%%%%%%% diff from: base files for restore (from kyxtmyvl 599b231d (rebased revision))
\\\\\\\        to: mppzrnto d3505609 "Add docs/ignore* to .gitignore to exclude documentation ignore files" (rebase destination)
+# EKS Inference Cluster Terraform Stack
+
+This stack provisions an Amazon EKS cluster for inference testing with a small untained system node group and a fixed two-node accelerator node group.
+
+## Why the default is `g5.xlarge`
+
+Your existing manifests under `.kube/` request `nvidia.com/gpu` and set `runtimeClassName: nvidia`, so they need NVIDIA-backed worker nodes.
+
+`inf.xlarge` is not a valid AWS instance type, and the closest real option (`inf2.xlarge`) is an **Inferentia/Neuron** accelerator, not an NVIDIA GPU.
+
+## What this stack creates
+
+- VPC with public/private subnets across 2 AZs
+- EKS control plane
+- One untained system node group with **1 node**
+- One fixed-size managed accelerator node group with **2 nodes**
+- EKS access entries for admin IAM principals
+- EBS CSI addon with IRSA
+
+## Review this first
+
+1. `docs/eks_senior_review.md`
+2. `terraform/modules/eks-inference/main.tf`
+3. `.kube/eks/ray/ray-vllm-service.yaml`
+
+## The only commands that matter at a glance
+
+- `scripts/eks/preflight.sh`
+- `scripts/eks/up-vllm.sh`
+- `scripts/eks/up-ray-vllm.sh`
+
+## Are we really using Bash to run Terraform?
+
+Yes, but only as a convenience layer.
+
+- **Terraform is still the real infrastructure tool**
+- the Bash scripts just wrap normal Terraform commands such as `init`, `plan`, `apply`, and `destroy`
+- this keeps the workflow simpler for people who are new to Terraform and also lets the repo fall back to Docker when Terraform is not installed locally
+
+## Helper script groups
+
+### Review / preflight
+- `scripts/eks/preflight.sh`
+
+### Main entrypoints
+- `scripts/eks/up.sh`
+- `scripts/eks/up-vllm.sh`
+- `scripts/eks/up-ray-vllm.sh`
+
+### Lower-level Terraform helpers
+- `scripts/eks/init.sh`
+- `scripts/eks/plan.sh`
+- `scripts/eks/apply.sh`
+- `scripts/eks/destroy.sh`
+- `scripts/eks/kubeconfig.sh`
+
+### Kubernetes addon / validation helpers
+- `scripts/eks/install-accelerator-plugin.sh`
+- `scripts/eks/validate.sh`
+- `scripts/eks/deploy-vllm.sh`
+- `scripts/eks/validate-vllm.sh`
+- `scripts/eks/install-kuberay.sh`
+- `scripts/eks/deploy-ray-vllm.sh`
+- `scripts/eks/validate-ray-vllm.sh`
+
+## AWS prerequisites
+
+- AWS account with quota for `g5.xlarge` in your chosen region
+- An IAM principal with permissions for VPC, EKS, EC2, IAM, and EBS CSI addon creation
+- AWS CLI configured locally
+- `kubectl`, `helm`, and either `terraform` or `docker`
+
+Before any Terraform apply, `scripts/eks/up*.sh` runs `scripts/eks/preflight.sh` to verify credentials, region enablement, EKS reachability, and whether `g5.xlarge` or `g6.xlarge` is offered.
+
+## Minimal deploy sequence on AWS
+
+```bash
+cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
+$EDITOR terraform/stacks/eks-inference/terraform.tfvars
+
+export AWS_PROFILE=your-profile
+export AWS_REGION=us-west-2
+export HF_TOKEN="hf_xxx"
+export VLLM_API_KEY="supersecretkey"
+
+scripts/eks/preflight.sh
+scripts/eks/up-vllm.sh
+```
+
+## Malaysia / G6 fallback
+
+Malaysia is `ap-southeast-5`, and it is an opt-in region for AWS accounts.
+
+```bash
+export AWS_PROFILE=your-profile
+export AWS_REGION=ap-southeast-5
+scripts/eks/preflight.sh
+```
+
+If preflight recommends `g6.xlarge`, update `terraform.tfvars` accordingly and run `scripts/eks/up-vllm.sh`.
+
+## Ray-backed distributed vLLM on EKS
+
+Ray is **not strictly required** by vLLM for multi-node sharding. vLLM also supports native multi-node startup without Ray. This repo implements the **Ray/KubeRay path** because it is more Kubernetes-native on EKS.
+
+## Resource sizing notes
+
+- `g5.xlarge` provides 1 GPU, 4 vCPUs, and 16 GiB memory
+- EKS vLLM overlay requests `2 CPU / 10 GiB / 1 GPU`
+- Ray worker requests `2 CPU / 10 GiB / 1 GPU`
+- Ray head and operators are intended to run on the system node
+++++++ kyxtmyvl 599b231d (rebased revision)
# EKS Inference Cluster Terraform Stack

This stack provisions an Amazon EKS cluster for inference testing with a small untained system node group and a fixed two-node accelerator node group.

## Why the default is `g5.xlarge`

Your existing manifests under `.kube/` request `nvidia.com/gpu` and set `runtimeClassName: nvidia`, so they need NVIDIA-backed worker nodes.

`inf.xlarge` is not a valid AWS instance type, and the closest real option (`inf2.xlarge`) is an **Inferentia/Neuron** accelerator, not an NVIDIA GPU.

## What this stack creates

- VPC with public/private subnets across 2 AZs
- EKS control plane
- One untained system node group with **1 node**
- One fixed-size managed accelerator node group with **2 nodes**
- EKS access entries for admin IAM principals
- EBS CSI addon with IRSA

## Quick review first

1. `docs/eks_terraform_quick_review.md`
2. `terraform/modules/eks-inference/main.tf`
3. `.kube/eks/ray/ray-vllm-service.yaml`

## The only commands that matter at a glance

- `scripts/eks/preflight.sh`
- `scripts/eks/up-vllm.sh`
- `scripts/eks/up-ray-vllm.sh`

## Are we really using Bash to run Terraform?

Yes, but only as a convenience layer.

- **Terraform is still the real infrastructure tool**
- the Bash scripts just wrap normal Terraform commands such as `init`, `plan`, `apply`, and `destroy`
- this keeps the workflow simpler for people who are new to Terraform and also lets the repo fall back to Docker when Terraform is not installed locally

## Helper script groups

### Review / preflight
- `scripts/eks/preflight.sh`

### Main entrypoints
- `scripts/eks/up.sh`
- `scripts/eks/up-vllm.sh`
- `scripts/eks/up-ray-vllm.sh`

### Lower-level Terraform helpers
- `scripts/eks/init.sh`
- `scripts/eks/plan.sh`
- `scripts/eks/apply.sh`
- `scripts/eks/destroy.sh`
- `scripts/eks/kubeconfig.sh`

### Kubernetes addon / validation helpers
- `scripts/eks/install-accelerator-plugin.sh`
- `scripts/eks/validate.sh`
- `scripts/eks/deploy-vllm.sh`
- `scripts/eks/validate-vllm.sh`
- `scripts/eks/install-kuberay.sh`
- `scripts/eks/deploy-ray-vllm.sh`
- `scripts/eks/validate-ray-vllm.sh`

## AWS prerequisites

- AWS account with quota for `g5.xlarge` in your chosen region
- An IAM principal with permissions for VPC, EKS, EC2, IAM, and EBS CSI addon creation
- AWS CLI configured locally
- `kubectl`, `helm`, and either `terraform` or `docker`

Before any Terraform apply, `scripts/eks/up*.sh` runs `scripts/eks/preflight.sh` to verify credentials, region enablement, EKS reachability, and whether `g5.xlarge` or `g6.xlarge` is offered.

## Minimal deploy sequence on AWS

```bash
cp terraform/stacks/eks-inference/terraform.tfvars.example terraform/stacks/eks-inference/terraform.tfvars
$EDITOR terraform/stacks/eks-inference/terraform.tfvars

export AWS_PROFILE=your-profile
export AWS_REGION=us-west-2
export HF_TOKEN="hf_xxx"
export VLLM_API_KEY="supersecretkey"

scripts/eks/preflight.sh
scripts/eks/up-vllm.sh
```

## Malaysia / G6 fallback

Malaysia is `ap-southeast-5`, and it is an opt-in region for AWS accounts.

```bash
export AWS_PROFILE=your-profile
export AWS_REGION=ap-southeast-5
scripts/eks/preflight.sh
```

If preflight recommends `g6.xlarge`, update `terraform.tfvars` accordingly and run `scripts/eks/up-vllm.sh`.

## Ray-backed distributed vLLM on EKS

Ray is **not strictly required** by vLLM for multi-node sharding. vLLM also supports native multi-node startup without Ray. This repo implements the **Ray/KubeRay path** because it is more Kubernetes-native on EKS.

## Resource sizing notes

- `g5.xlarge` provides 1 GPU, 4 vCPUs, and 16 GiB memory
- EKS vLLM overlay requests `2 CPU / 10 GiB / 1 GPU`
- Ray worker requests `2 CPU / 10 GiB / 1 GPU`
- Ray head and operators are intended to run on the system node
>>>>>>> conflict 1 of 1 ends
