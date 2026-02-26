
# Inference Deployment

Tools, playbooks and notes for deploying inference engines (LLMs and GPU-based models).

## Overview

This repository collects documentation and deployment guidance for running model inference efficiently on GPU and hybrid CPU/GPU setups. It contains operational playbooks, research notes, and examples to help deploy and optimize inference workloads.

## Contents

- `docs/` — deployment playbooks and research notes

## Quickstart

1. Review the deployment playbook: `docs/hybrid_gpu_inference_playbook.md`
2. Read the research notes for background and experiments: `docs/LLM Inference on GPU_ Research Notes.md`
3. Follow the steps in the playbook for environment setup (drivers, CUDA, container runtime) and model serving.

## Documentation

- Hybrid GPU inference playbook: `docs/hybrid_gpu_inference_playbook.md`
- LLM inference research notes: `docs/LLM Inference on GPU_ Research Notes.md`

## Using Qwen3.5-27B-GGUF (Q4_K_M)

This repo will store models in `./hf_cache` so downloads stay inside the project.

1) Create the cache directory and export your HF token:

```bash
mkdir -p hf_cache
export HF_TOKEN="hf_xxx"
```

2) Pre-download the quantized model into the repo cache (recommended):

```bash
pip install --upgrade huggingface_hub
HF_TOKEN=$HF_TOKEN python scripts/download_qwen.py
```

3) Or run the model directly via Docker's model runner (this will pull from hf.co):

```bash
docker model run hf.co/unsloth/Qwen3.5-27B-GGUF:Q4_K_M
```

Notes:
- The `snapshot_download` in `scripts/download_qwen.py` uses `revision="Q4_K_M"` to fetch the Q4_K_M quantized artifact.
- Ensure you have enough disk space in `./hf_cache` and that `HF_TOKEN` is set if the model requires authentication.


