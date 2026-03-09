#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd python3
require_env VLLM_API_KEY

NAMESPACE="${NAMESPACE:-inference-engine}"
MANIFEST_PATH="${ROOT_DIR}/.kube/eks/ray/ray-vllm-service.yaml"
BACKUP_PATH="${ROOT_DIR}/.kube/eks/ray/ray-vllm-service.yaml.bak"
CONTEXT_WINDOWS="${CONTEXT_WINDOWS:-32768 65536 131072}"
PROMPT="${PROMPT:-Explain the tradeoff between long context windows and TTFT in vLLM.}"
MAX_TOKENS="${MAX_TOKENS:-256}"

cp "${MANIFEST_PATH}" "${BACKUP_PATH}"
cleanup() {
  mv "${BACKUP_PATH}" "${MANIFEST_PATH}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for context_window in ${CONTEXT_WINDOWS}; do
  echo "==> Testing max_model_len=${context_window}"

  CONTEXT_WINDOW="${context_window}" MANIFEST_PATH="${MANIFEST_PATH}" python3 - <<'PY'
from pathlib import Path
import os
import re

path = Path(os.environ["MANIFEST_PATH"])
window = os.environ["CONTEXT_WINDOW"]
text = path.read_text()
text = re.sub(r"max_model_len:\s*\d+", f"max_model_len: {window}", text, count=1)
path.write_text(text)
PY

  "${ROOT_DIR}/scripts/eks/deploy-ray-vllm.sh"
  "${ROOT_DIR}/scripts/eks/validate-ray-vllm.sh"
  PROMPT="${PROMPT}" MAX_TOKENS="${MAX_TOKENS}" "${ROOT_DIR}/scripts/eks/benchmark-ray-vllm.sh"
  echo

  cp "${BACKUP_PATH}" "${MANIFEST_PATH}"
done
