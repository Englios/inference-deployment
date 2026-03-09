#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${TERRAFORM_IMAGE:-hashicorp/terraform:1.9.8}"
if command -v terraform >/dev/null 2>&1; then exec terraform "$@"; fi
if ! command -v docker >/dev/null 2>&1; then echo "Missing required command: terraform or docker" >&2; exit 1; fi
docker_args=(run --rm -i -v "${ROOT_DIR}:/workspace" -w /workspace)
if [[ -d "${HOME}/.aws" ]]; then docker_args+=(-v "${HOME}/.aws:/root/.aws:ro"); fi
for env_name in AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  if [[ -n "${!env_name:-}" ]]; then docker_args+=(-e "${env_name}=${!env_name}"); fi
done
exec docker "${docker_args[@]}" "${IMAGE}" "$@"
