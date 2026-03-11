#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd python3
require_env VLLM_API_KEY

NAMESPACE="${NAMESPACE:-inference-engine}"
CONFIG_PATH="${EKS_INFERENCE_CONFIG}"
BACKUP_PATH="${EKS_INFERENCE_CONFIG}.bak"
CONTEXT_WINDOWS="${CONTEXT_WINDOWS:-32768 65536 131072}"
PROMPT="${PROMPT:-Explain the tradeoff between long context windows and TTFT in vLLM.}"
MAX_TOKENS="${MAX_TOKENS:-256}"

cp "${CONFIG_PATH}" "${BACKUP_PATH}"
cleanup() {
  mv "${BACKUP_PATH}" "${CONFIG_PATH}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for context_window in ${CONTEXT_WINDOWS}; do
  echo "==> Testing max_model_len=${context_window}"

  CONTEXT_WINDOW="${context_window}" CONFIG_PATH="${CONFIG_PATH}" python3 - <<'PY'
from pathlib import Path
import json
import os

path = Path(os.environ["CONFIG_PATH"])
window = os.environ["CONTEXT_WINDOW"]
payload = json.loads(path.read_text())
payload["engine"]["max_model_len"] = int(window)
path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  "${ROOT_DIR}/scripts/eks/deploy-ray-vllm.sh"
  "${ROOT_DIR}/scripts/eks/validate-ray-vllm.sh"
  PROMPT="${PROMPT}" MAX_TOKENS="${MAX_TOKENS}" "${ROOT_DIR}/scripts/eks/benchmark-ray-vllm.sh"
  echo

  cp "${BACKUP_PATH}" "${CONFIG_PATH}"
done
