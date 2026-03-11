## Task: Add Ray Metrics Port & Worker ServiceMonitor
**Date**: 2026-03-11 | **Task ID**: metrics-port-worker-monitor

### Changes Made
1. **ray-vllm-service.yaml.tpl** (line 71-72): Added containerPort 8080 with name: metrics after the dashboard port block
2. **ray-worker-servicemonitor.yaml** (NEW): Created ServiceMonitor targeting `ray.io/node-type: worker` pods, scraping `/metrics` on port 8080 every 30s
3. **ray-metrics-service.yaml**: Verified existing (no changes needed) — already targets port 8080

### Verification
- ✅ `grep 'containerPort: 8080' .eks/ray/ray-vllm-service.yaml.tpl` → Found at line 71
- ✅ `grep 'ray.io/node-type: worker' .eks/monitoring/ray-worker-servicemonitor.yaml` → Present
- ✅ `grep 'targetPort: 8080' .eks/monitoring/ray-metrics-service.yaml` → Present at line 14

### Pattern Learned
ServiceMonitor structure (all metrics endpoints follow same pattern):
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <resource>-metrics
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - inference-engine
  selector:
    matchLabels:
      <selector-label>: <value>
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

---

## Task: Parameterize Ray Serve Autoscaling Replicas
**Date**: 2026-03-11 | **Task ID**: ray-autoscaling-params | **Status**: ✅ Complete

### Changes Made
1. **ray-vllm-service.yaml.tpl** (lines 25-26): 
   - Changed `min_replicas: 1` → `min_replicas: ${ray_serve_min_replicas}`
   - Changed `max_replicas: 1` → `max_replicas: ${ray_serve_max_replicas}`

2. **inference-profile.json** (ray object, after client_port):
   - Added `"serve_min_replicas": 1` (default)
   - Added `"serve_max_replicas": 4` (allows scaling)

3. **inference_config.py** (flatten() function, after ray_client_port):
   - Added mapping: `"ray_serve_min_replicas": str(ray["serve_min_replicas"])`
   - Added mapping: `"ray_serve_max_replicas": str(ray["serve_max_replicas"])`

### Verification
- ✅ `grep 'ray_serve_min_replicas' .eks/ray/ray-vllm-service.yaml.tpl` → Found at line 25
- ✅ `grep 'ray_serve_max_replicas' .eks/ray/ray-vllm-service.yaml.tpl` → Found at line 26
- ✅ No literal `min_replicas: 1` or `max_replicas: 1` remain in autoscaling_config
- ✅ `grep 'serve_min_replicas' .eks/inference-profile.json` → Present with default value 1
- ✅ `grep 'serve_max_replicas' .eks/inference-profile.json` → Present with default value 4
- ✅ `grep 'ray_serve_min_replicas' scripts/eks/inference_config.py` → Mapping exists
- ✅ Template renders successfully: `python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane ray-vllm --output-root /tmp/test`
- ✅ Rendered output shows `min_replicas: 1` and `max_replicas: 4` correctly substituted
- ✅ JSON validation: `python3 -m json.tool .eks/inference-profile.json` passes
- ✅ Python syntax: `inference_config.py` imports cleanly

### Pattern Learned
**Ray Serve autoscaling parameterization** follows the same ${...} substitution pattern as workerGroupSpecs (lines 87-88 in template):
- Profile defines new fields under `ray` object (sibling to `service_name`, `ray_version`, etc.)
- Config.py flatten() maps `ray[key]` → `ray_<key>` template variable
- Template uses `${ray_serve_min_replicas}` and `${ray_serve_max_replicas}` for substitution
- Defaults in profile: min=1 (initial replicas), max=4 (allows 3x horizontal scaling)

### Key Insights
- Hardcoded autoscaling replicas (1→1) was a bottleneck for Ray Serve — now profiles can vary serving capacity independently from worker cluster scaling
- Defaults (1-4) align with experimental baseline: minimal initial footprint, room to scale if needed
- Pattern aligns with existing ray.worker parameterization, making it consistent for operators

---

## Task: Align Ray Version in Profile
**Date**: 2026-03-11 | **Task ID**: ray-version-alignment | **Status**: ✅ Complete

### Problem
Profile had `ray.ray_version: 2.52.0` but actual image tag was `anyscale/ray-llm:2.54.0-py311-cu128`. Mismatch created confusion about actual deployed version.

### Changes Made
1. **inference-profile.json** (line 32): Updated `ray_version` from `2.52.0` → `2.54.0`

### Verification
- ✅ JSON valid: `python3 -c "import json; json.load(open('.eks/inference-profile.json'))"` passes
- ✅ New version present: `grep '2.54.0' .eks/inference-profile.json` → 2 matches (ray_version + image tag)
- ✅ Old version removed: `grep '2.52.0' .eks/inference-profile.json` → 0 matches
- ✅ Config mapping verified: Line 53 of `inference_config.py` maps `ray["ray_version"]` → `ray_version` template var (existing, no change needed)

### Key Insight
Profile `ray_version` field acts as source of truth for templated rendering. Image tag and version field should always match. Template (`ray-vllm-service.yaml.tpl`) already uses `${ray_version}` correctly — only profile value needed sync.

---

## Task: Add Dynamo VllmWorker Pipeline Parallel Size Argument
**Date**: 2026-03-11 | **Task ID**: dynamo-pp-bug-fix | **Status**: ✅ Complete

### Problem
Dynamo agg.yaml.tpl had `--tensor-parallel-size` and `--data-parallel-size` but was missing `--pipeline-parallel-size` in worker command args. This caused `engine.pipeline_parallel_size: 2` from inference-profile.json to be silently dropped, resulting in incorrect model sharding (default PP=1 instead of intended PP=2).

### Changes Made
1. **.eks/dynamo/vllm/agg.yaml.tpl** (line 96): Added new line after `--tensor-parallel-size ${tensor_parallel_size}`:
   ```
   --pipeline-parallel-size ${pipeline_parallel_size}
   ```

### Verification
- ✅ `grep 'pipeline-parallel-size' .eks/dynamo/vllm/agg.yaml.tpl` → Found at line 96
- ✅ Render test: `python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane dynamo-vllm --output-root /tmp/render-test` → Success
- ✅ Rendered output check: `grep 'pipeline-parallel-size' /tmp/render-test/dynamo/vllm/agg.yaml` → Returns `--pipeline-parallel-size 2` (correctly substituted from profile)

### Pattern Observed
Dynamo vLLM worker args follow exact same parameterization pattern as Ray:
- Profile defines `engine.pipeline_parallel_size: 2`
- inference_config.py already maps it via `flatten()` → `pipeline_parallel_size` template var
- Template uses `${pipeline_parallel_size}` for substitution
- No pipeline-routing, NIXL, or KV-routing flags added (those belong in separate tasks)

### Key Insight
This was a simple omission in the initial Dynamo template — Ray had PP support all along (line 20 of ray-vllm-service.yaml.tpl shows `pipeline_parallel_size: ${pipeline_parallel_size}`), but Dynamo was missing it. The infrastructure to support PP substitution was already in place; only the worker args were incomplete.

---

## Task: Create terraform.g7e-1x2.tfvars and Add node_group_taints Variable
**Date**: 2026-03-11 | **Task ID**: g7e-1x2-baseline-config | **Status**: ✅ Complete

### Problem
Missing terraform configuration for single-node baseline experiments. The tfvars file and node_group_taints variable needed to support 1x2 baseline shape (1 node × 2 GPUs).

### Changes Made
1. **terraform.g7e-1x2.tfvars** (NEW): Created single-node baseline config
   - Copied structure from terraform.g7e-2x2.tfvars
   - Set `node_group_size = 1` (vs 2 in g7e-2x2)
   - Used `gpu_node_instance_types = ["g7e.12xlarge"]` (2 GPUs per node, so 1×2 total)
   - All other settings match: 500 GiB disk, system node t3.large, Owner=platform tag

2. **variables.tf** (lines 129-133): Added node_group_taints variable
   - Type: `list(object({ key = string, value = string, effect = string }))`
   - Default: `[]` (no taints applied unless specified)
   - Positioned after node_group_labels (line 127) for logical grouping
   - Follows same pattern as node_group_labels (similar map-like structure)

### Verification
- ✅ `ls terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` → File exists, 16 lines
- ✅ `grep 'node_group_size.*1' terraform.g7e-1x2.tfvars` → Returns `node_group_size = 1`
- ✅ `grep 'g7e.12xlarge' terraform.g7e-1x2.tfvars` → Instance type correct
- ✅ `grep 'node_group_taints' variables.tf` → Variable declared at line 129
- ✅ Variable type matches pattern: `list(object({ key = string, value = string, effect = string }))`
- ✅ Variables.tf total lines: 151 (was 145, +6 for new variable block)

### Key Insights
- **Naming convention**: `terraform.{instance-shape}-{node-count}x{gpus-per-node}.tfvars`
  - `g7e-2x2.tfvars`: 2 nodes × 2 GPUs = 4 total
  - `g7e-1x4.tfvars`: 1 node × 4 GPUs (g7e.24xlarge) = 4 total
  - `g7e-1x2.tfvars`: 1 node × 2 GPUs (g7e.12xlarge) = 2 total (NEW)
- **node_group_taints pattern**: Follows same parameterization as node_group_labels — declared but not yet wired into main.tf module call (that's a follow-up task)
- Single-node baseline enables minimal overhead experiments for model serving evaluation


---

## Task: Fix Dynamo Metrics Port-Forward in Benchmark and Validate Scripts
**Date**: 2026-03-11 | **Task ID**: dynamo-metrics-port-forward-fix | **Status**: ✅ Complete

### Problem
- `benchmark-dynamo-vllm.sh` line 28 hardcoded `:8000` instead of `:9090` for metrics port-forward
- `validate-dynamo-vllm.sh` line 13 only forwarded HTTP port, no metrics port at all

### Changes Made
1. **benchmark-dynamo-vllm.sh** (line 28): Changed `:8000` → `:9090` in kubectl port-forward command
2. **validate-dynamo-vllm.sh** (line 10): Added `METRICS_PORT="${METRICS_PORT:-18001}"` variable declaration
3. **validate-dynamo-vllm.sh** (line 14): Added metrics port-forward `"${METRICS_PORT}:9090"` to kubectl command

### Verification
- ✅ `grep ':8000' scripts/eks/benchmark-dynamo-vllm.sh` → 0 matches (hardcoded port removed)
- ✅ `grep 'METRICS_PORT' scripts/eks/validate-dynamo-vllm.sh` → 2 matches (variable added + used)
- ✅ `grep ':9090' scripts/eks/benchmark-dynamo-vllm.sh` → Match found
- ✅ `grep ':9090' scripts/eks/validate-dynamo-vllm.sh` → Match found

### Key Insight
Dynamo metrics port is **9090** (from `.eks/inference-profile.json` runtime.metrics_port), not 8000. Both benchmark and validate scripts needed alignment with the correct port. Pattern matches Ray benchmark script (`benchmark-ray-vllm.sh`) which also uses metrics_port from profile.

---

## Task: Ansible Infra Fixes (Destroy Auto-Approve + Secret Scope)
**Date**: 2026-03-11 | **Task ID**: ansible-infra-fixes | **Status**: ✅ Complete

### Problem
- `scripts/eks/destroy.sh` required manual approval for terraform destroy (unsafe for automation)
- `ansible/playbooks/cleanup_namespace.yml` deleted ALL non-default secrets (too broad, affects other lanes)

### Changes Made
1. **scripts/eks/destroy.sh** (line 19): Added `-auto-approve` flag to terraform destroy command
2. **ansible/playbooks/cleanup_namespace.yml** (line 26): Changed secret deletion from `grep -v 'default-token'` to `grep -E '(ray-vllm|dynamo-vllm|hf-token|vllm)'` for lane-scoped cleanup

### Verification
- ✅ `grep 'auto-approve' scripts/eks/destroy.sh` → Match found
- ✅ `grep 'ray-vllm\|dynamo-vllm\|hf-token' ansible/playbooks/cleanup_namespace.yml` → Match found (scoped pattern)
- ✅ Old broad pattern `grep -v 'default-token'` removed

### Key Insight
Ansible cleanup should only delete secrets created by the specific lane being cleaned up, not all non-default secrets. The scoped pattern matches: `ray-vllm-*`, `dynamo-vllm-*`, `hf-token-*`, and `vllm-*` secrets.
