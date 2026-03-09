#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
STACK_DIR="${ROOT_DIR}/terraform/stacks/eks-inference"
TF_BIN="${ROOT_DIR}/scripts/eks/terraform.sh"

require_cmd() {
  local cmd="$1"

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "${name} must be exported before running this script." >&2
    exit 1
  fi
}

run_step() {
  local label="$1"
  shift

  echo "==> ${label}"
  "$@"
}
