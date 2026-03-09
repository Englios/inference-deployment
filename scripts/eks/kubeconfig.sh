#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd aws

cluster_name="${CLUSTER_NAME:-$(${TF_BIN} -chdir="terraform/stacks/eks-inference" output -raw cluster_name)}"
region="${AWS_REGION:-$(${TF_BIN} -chdir="terraform/stacks/eks-inference" output -raw aws_region)}"

aws eks update-kubeconfig --region "${region}" --name "${cluster_name}"
