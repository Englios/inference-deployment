#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

"${TF_BIN}" -chdir="terraform/stacks/eks-inference" init
