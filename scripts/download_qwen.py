#!/usr/bin/env python3
"""Download the quantized GGUF model into the repo-local hf_cache.

Usage:
  HF_TOKEN=<token> python scripts/download_qwen.py
"""

import os
from huggingface_hub import snapshot_download
from dotenv import load_dotenv

load_dotenv()


def main():
    repo_id = "unsloth/Qwen3.5-27B-GGUF"
    local_dir = os.path.join(os.getcwd(), "hf_cache", "unsloth", "Qwen3.5-27B-GGUF")
    os.makedirs(local_dir, exist_ok=True)

    token = os.getenv("HF_TOKEN")
    print(f"Downloading {repo_id} to {local_dir} ...")
    snapshot_download(
        repo_id,
        local_dir=local_dir,
        local_files_only=False,
        allow_patterns=["Qwen3.5-27B-Q3_K_M.gguf", "*README*", "*.json"],
        token=token,
    )
    print("Download finished.")


if __name__ == "__main__":
    main()
