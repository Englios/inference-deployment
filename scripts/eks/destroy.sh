#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

TFVARS_FILE="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"

if [[ ! -f "${TFVARS_FILE}" ]]; then
  echo "Missing ${TFVARS_FILE}." >&2
  exit 1
fi

if [[ "${TFVARS_FILE}" != "${STACK_DIR}/"* ]]; then
  echo "TFVARS_FILE must live under ${STACK_DIR}." >&2
  exit 1
fi

tfvars_relative="${TFVARS_FILE#${STACK_DIR}/}"

"${TF_BIN}" -chdir="terraform/stacks/eks-inference" destroy -var-file="${tfvars_relative}"
