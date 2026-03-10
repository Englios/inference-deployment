#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PLAN_FILE="${PLAN_FILE:-tfplan}"
TFVARS_FILE="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "Missing ${TFVARS_FILE}. Copy terraform.tfvars.example first or point TFVARS_FILE at an experiment-specific tfvars file." >&2
  exit 1
fi

if [[ "${TFVARS_FILE}" != "${STACK_DIR}/"* ]]; then
  echo "TFVARS_FILE must live under ${STACK_DIR}." >&2
  exit 1
fi

tfvars_relative="${TFVARS_FILE#${STACK_DIR}/}"

"${TF_BIN}" \
  -chdir="terraform/stacks/eks-inference" \
  plan \
  -var-file="${tfvars_relative}" \
  -out="${PLAN_FILE}"
