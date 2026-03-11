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
