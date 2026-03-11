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
