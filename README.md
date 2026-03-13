
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

- `.kube/` — Kubernetes manifests (base + engine/middleware deployments)
- `app/` — OpenAI-compatible middleware gateway app source
- `scripts/` — utility scripts (model download, smoke tests, etc.)
- `docs/` — playbooks and reference notes

## Quickstart

1. Review the deployment playbook: `docs/hybrid_gpu_inference_playbook.md`
2. Read the research notes for background and experiments: `docs/LLM Inference on GPU_ Research Notes.md`
3. Follow the steps in the playbook for environment setup (drivers, CUDA, container runtime) and model serving.
4. Rotate gateway client auth keys when needed: `scripts/rotate_gateway_keys.sh`

## Documentation

- Hybrid GPU inference playbook: `docs/hybrid_gpu_inference_playbook.md`
- LLM inference research notes: `docs/LLM Inference on GPU_ Research Notes.md`

## Ansible: Dynamo Platform Install (Debian node)

Use the Ansible playbook at `ansible/dynamo-platform-install.yml` to install:

- `dynamo-crds` (required before platform for recent versions)
- `dynamo-platform`

The playbook also:

- Pins operator/etcd/nats workloads to a target node hostname (default: `debian`)
- Overrides kube-rbac-proxy image to `quay.io/brancz/kube-rbac-proxy:v0.15.0`

Run it with local kube context:

```bash
ansible-playbook ansible/dynamo-platform-install.yml
```

Override defaults if needed:

```bash
ansible-playbook ansible/dynamo-platform-install.yml \
  -e release_version=0.9.1 \
  -e target_node_hostname=debian \
  -e namespace=dynamo-system
```

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
