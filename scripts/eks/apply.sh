#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

PLAN_FILE="${PLAN_FILE:-tfplan}"

if [[ -f "${STACK_DIR}/${PLAN_FILE}" ]]; then
  "${TF_BIN}" -chdir="terraform/stacks/eks-inference" apply "${PLAN_FILE}"
else
  "${TF_BIN}" -chdir="terraform/stacks/eks-inference" apply -var-file="terraform.tfvars"
fi
