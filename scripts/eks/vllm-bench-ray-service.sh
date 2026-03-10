#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

require_cmd kubectl

NAMESPACE="${NAMESPACE:-inference-engine}"
MODEL="${MODEL:-openai/gpt-oss-120b}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-gpt-oss-120b}"
HEAD_POD="${HEAD_POD:-$(kubectl -n "${NAMESPACE}" get pod -l ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')}"
SERVICE_URL="${SERVICE_URL:-http://ray-vllm-serve-svc.${NAMESPACE}.svc.cluster.local:8000}"
BACKEND="${BACKEND:-openai-chat}"
DATASET_NAME="${DATASET_NAME:-random}"
NUM_PROMPTS="${NUM_PROMPTS:-20}"
RANDOM_INPUT_LEN="${RANDOM_INPUT_LEN:-2048}"
RANDOM_OUTPUT_LEN="${RANDOM_OUTPUT_LEN:-256}"
MAX_CONCURRENCY="${MAX_CONCURRENCY:-4}"
TOKENIZER="${TOKENIZER:-${MODEL}}"

kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/node-type=head --timeout=1800s
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod -l ray.io/group=gpu-workers --timeout=1800s

kubectl -n "${NAMESPACE}" exec "${HEAD_POD}" -- \
  vllm bench serve \
  --backend "${BACKEND}" \
  --base-url "${SERVICE_URL}" \
  --endpoint /v1/chat/completions \
  --model "${MODEL}" \
  --served-model-name "${SERVED_MODEL_NAME}" \
  --tokenizer "${TOKENIZER}" \
  --dataset-name "${DATASET_NAME}" \
  --num-prompts "${NUM_PROMPTS}" \
  --random-input-len "${RANDOM_INPUT_LEN}" \
  --random-output-len "${RANDOM_OUTPUT_LEN}" \
  --max-concurrency "${MAX_CONCURRENCY}"
