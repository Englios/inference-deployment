#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PLAN_FILE="${PLAN_FILE:-tfplan}"
TFVARS_FILE="${TFVARS_FILE:-${STACK_DIR}/terraform.tfvars}"

if [[ "${TFVARS_FILE}" != "${STACK_DIR}/"* ]]; then
  echo "TFVARS_FILE must live under ${STACK_DIR}." >&2
  exit 1
fi

tfvars_relative="${TFVARS_FILE#${STACK_DIR}/}"

if [[ -f "${STACK_DIR}/${PLAN_FILE}" ]]; then
  "${TF_BIN}" -chdir="terraform/stacks/eks-inference" apply "${PLAN_FILE}"
else
  if [[ ! -f "${TFVARS_FILE}" ]]; then
    echo "Missing ${TFVARS_FILE}." >&2
    exit 1
  fi

  "${TF_BIN}" -chdir="terraform/stacks/eks-inference" apply -var-file="${tfvars_relative}"
fi
