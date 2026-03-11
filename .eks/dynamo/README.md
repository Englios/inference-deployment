# Dynamo EKS lane (planned)

This directory is reserved for Dynamo-backed EKS experiment assets.

## Intended structure

- `.eks/dynamo/vllm/` — DynamoGraphDeployment manifests and overlays for vLLM
- `.eks/dynamo/sglang/` — DynamoGraphDeployment manifests and overlays for SGLang
- `.eks/dynamo/trtllm/` — DynamoGraphDeployment manifests and overlays for TensorRT-LLM
- `.eks/dynamo/model-cache/` — PVC and model download jobs modeled after Dynamo recipes
- `.eks/dynamo/monitoring/` — Service and ServiceMonitor assets for Dynamo frontend/workers

## Initial assets now included

- `hf-token-secret.example.yaml` — example Hugging Face secret shape

Template-backed variants now exist for the shared profile workflow:

- `namespace.yaml.tpl`
- `model-cache-pvc.yaml.tpl`
- `vllm/agg.yaml.tpl`
- `service-llm.yaml.tpl`

These render from `.eks/inference-profile.json` into `.eks/rendered/`.

Observability assets are defined by template-backed variants in `.eks/monitoring/` for the shared render path.

## Planned lane names

- `dynamo-vllm`
- `dynamo-sglang`
- `dynamo-trtllm`

## Ansible contract

Future lane support should plug into the generic Ansible playbooks:

- `ansible/playbooks/lane_deploy.yml`
- `ansible/playbooks/lane_validate.yml`
- `ansible/playbooks/lane_benchmark.yml`
- `ansible/playbooks/lane_run.yml`

Each Dynamo lane should preserve the same benchmark contract used elsewhere in this repo:

- OpenAI-compatible serving endpoint
- `GET /health`
- `GET /v1/models`
- Prometheus scrape target(s)
- repeatable benchmark capture compatible with the shared benchmark backend or a lane-specific equivalent

## Notes on observability

- Upstream Dynamo guidance uses `PodMonitor` for application/frontend/worker metrics.
- Operator metrics are expected to come from the Dynamo Helm install's own `ServiceMonitor`.
- Structured JSONL logging is enabled in the example manifest so a future Loki/Alloy setup can be layered on cleanly.

## Design intent

Dynamo is treated as a production-candidate experiment lane, not yet the repo-wide default abstraction. The repo stays Kubernetes-first, with Dynamo added as an optional runtime/orchestration path.

## Shared profile workflow

Ray and Dynamo now share one profile source:

- `.eks/inference-profile.json`

Use it to change model, TP/PP, max model length, GPU memory utilization, and lane sizing without manually editing multiple manifests.

The deploy path uses rendered output under `.eks/rendered/`.
