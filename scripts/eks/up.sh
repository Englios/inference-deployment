#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

run_step "AWS preflight" "${ROOT_DIR}/scripts/eks/preflight.sh"
run_step "Terraform init" "${ROOT_DIR}/scripts/eks/init.sh"
run_step "Terraform plan" "${ROOT_DIR}/scripts/eks/plan.sh"
run_step "Terraform apply" "${ROOT_DIR}/scripts/eks/apply.sh"
run_step "Update kubeconfig" "${ROOT_DIR}/scripts/eks/kubeconfig.sh"
run_step "Install accelerator plugin" "${ROOT_DIR}/scripts/eks/install-accelerator-plugin.sh"
run_step "Validate cluster" "${ROOT_DIR}/scripts/eks/validate.sh"
