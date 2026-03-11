
# Inference Deployment

> **Note**: This repository is designed to be deployed on the infrastructure from [alif-homelab](https://github.com/Englios/alif-homelab). It is a standalone repository dedicated to managing AI inference engine deployments, separate from the main homelab infrastructure repo.

Tools, playbooks and notes for deploying inference engines (LLMs and GPU-based models).

## Overview

This repository collects documentation and deployment guidance for running model inference efficiently on GPU and hybrid CPU/GPU setups. It contains operational playbooks, research notes, and examples to help deploy and optimize inference workloads.

## Infrastructure

This inference engine deployment runs on a self-hosted Kubernetes cluster provisioned from the [alif-homelab](https://github.com/Englios/alif-homelab) repository. The homelab provides the underlying compute, networking, and storage infrastructure, while this repo focuses specifically on:

- Model serving and inference optimization
- Gateway/middleware configuration
- Deployment playbooks and operational tooling

See the [alif-homelab](https://github.com/Englios/alif-homelab) repo for the base infrastructure setup.

## Repo Layout

- `.kube/` — local Kubernetes manifests for dev workflows (base + engine/middleware deployments)
- `.eks/` — EKS deployment assets (`ray/manifests/`, `ray/templates/`, `monitoring/`); keep this to current supported deployment paths, not per-experiment variants
- `app/` — OpenAI-compatible middleware gateway app source
- `scripts/` — utility scripts (model download, smoke tests, etc.)
- `docs/` — playbooks and reference notes

## Quickstart

1. Review the deployment playbook: `docs/hybrid_gpu_inference_playbook.md`
2. Read the research notes for background and experiments: `docs/LLM Inference on GPU_ Research Notes.md`
3. Use the Ansible workflows in `ansible/README.md` for EKS experiment operations.
4. Rotate gateway client auth keys when needed: `scripts/rotate_gateway_keys.sh`

### EKS operator interface

Use Ansible as the supported interface for EKS experiment workflows:

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

Shell scripts under `scripts/eks/` are internal backend implementation details for those playbooks.

## Documentation

- Hybrid GPU inference playbook: `docs/hybrid_gpu_inference_playbook.md`
- LLM inference research notes: `docs/LLM Inference on GPU_ Research Notes.md`

## Using Qwen3.5-27B-GGUF (Q3_K_M)

This repo will store models in `./hf_cache` so downloads stay inside the project.

### Local Docker Compose

For local testing, use the docker-compose setup:

```bash
cd .docker
docker compose up -d
```

This runs:
- `llama.cpp` server (Q3_K_M quantized) on port 10000
- GPU check container (optional)

### Pre-download Model

1) Create the cache directory and export your HF token:

```bash
mkdir -p hf_cache
export HF_TOKEN="hf_xxx"
```

2) Pre-download the quantized model into the repo cache:

```bash
pip install --upgrade huggingface_hub
HF_TOKEN=$HF_TOKEN python scripts/download_qwen.py
```

Notes:
- The script uses `allow_patterns=["Qwen3.5-27B-Q3_K_M.gguf"]` to fetch the Q3_K_M quantized artifact.
- Ensure you have enough disk space in `./hf_cache` and that `HF_TOKEN` is set if the model requires authentication.
