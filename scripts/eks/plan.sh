#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PLAN_FILE="${PLAN_FILE:-tfplan}"

if [[ ! -f "${STACK_DIR}/terraform.tfvars" ]]; then
  echo "Missing ${STACK_DIR}/terraform.tfvars. Copy terraform.tfvars.example first." >&2
  exit 1
fi

"${TF_BIN}" \
  -chdir="terraform/stacks/eks-inference" \
  plan \
  -var-file="terraform.tfvars" \
  -out="${PLAN_FILE}"
