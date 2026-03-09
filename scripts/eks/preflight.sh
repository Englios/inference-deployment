#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd aws

TFVARS_FILE="${TFVARS_FILE:-${ROOT_DIR}/terraform/stacks/eks-inference/terraform.tfvars}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
AWS_PROFILE="${AWS_PROFILE:-}"

if [[ -z "${AWS_REGION}" && -f "${TFVARS_FILE}" ]]; then
  AWS_REGION="$(grep -E '^aws_region\s*=' "${TFVARS_FILE}" | head -n 1 | cut -d '"' -f2 || true)"
fi

if [[ -z "${AWS_REGION}" ]]; then
  echo "AWS_REGION is not set and could not be derived from terraform.tfvars." >&2
  exit 1
fi

AWS_CMD=(aws)

if [[ -n "${AWS_PROFILE}" ]]; then
  AWS_CMD+=(--profile "${AWS_PROFILE}")
fi

echo "== AWS EKS preflight =="
echo "Profile: ${AWS_PROFILE:-<default credential chain>}"
echo "Region:  ${AWS_REGION}"
echo

identity_json="$("${AWS_CMD[@]}" sts get-caller-identity --output json)"
echo "Authenticated identity:"
printf '%s\n' "${identity_json}"
echo

region_status="$("${AWS_CMD[@]}" account get-region-opt-status --region-name "${AWS_REGION}" --query 'RegionOptStatus' --output text 2>/dev/null || true)"

if [[ -z "${region_status}" || "${region_status}" == "None" ]]; then
  region_status="UNKNOWN"
fi

echo "Region opt-in status: ${region_status}"

if [[ "${region_status}" == "DISABLED" || "${region_status}" == "DISABLING" ]]; then
  echo "Region ${AWS_REGION} is not enabled for this account." >&2
  exit 1
fi

echo
echo "Checking EKS availability in ${AWS_REGION}..."
"${AWS_CMD[@]}" eks describe-addon-versions --region "${AWS_REGION}" --max-results 1 >/dev/null
echo "EKS API reachable in ${AWS_REGION}."
echo

candidate_instance_types=("g5.xlarge" "g6.xlarge")

if [[ "${AWS_REGION}" == "ap-southeast-5" ]]; then
  candidate_instance_types=("g6.xlarge" "g5.xlarge")
fi

echo "Checking candidate GPU instance offerings..."
available_types=()

for instance_type in "${candidate_instance_types[@]}"; do
  offering_count="$("${AWS_CMD[@]}" ec2 describe-instance-type-offerings --region "${AWS_REGION}" --location-type region --filters "Name=instance-type,Values=${instance_type}" --query 'length(InstanceTypeOfferings)' --output text)"

  if [[ "${offering_count}" =~ ^[1-9][0-9]*$ ]]; then
    available_types+=("${instance_type}")
    echo "  - ${instance_type}: offered in ${AWS_REGION}"
  else
    echo "  - ${instance_type}: not offered in ${AWS_REGION}"
  fi
done

echo

if [[ ${#available_types[@]} -eq 0 ]]; then
  echo "No tested GPU instance types (g5.xlarge or g6.xlarge) are offered in ${AWS_REGION}." >&2
  exit 1
fi

recommended_type="${available_types[0]}"

echo "Recommended accelerator node type for this region: ${recommended_type}"

if [[ "${AWS_REGION}" == "ap-southeast-5" && "${recommended_type}" == "g6.xlarge" ]]; then
  echo "Malaysia region detected: preferring g6.xlarge because AWS has announced G6 availability there and G5 may be harder to source."
fi

echo
echo "Suggested terraform overrides:"
echo "  aws_region = \"${AWS_REGION}\""
echo "  gpu_node_instance_types = [\"${recommended_type}\"]"
echo
echo "Preflight checks passed."
