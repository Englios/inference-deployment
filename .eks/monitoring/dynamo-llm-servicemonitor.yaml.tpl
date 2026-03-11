apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dynamo-llm-service
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - ${namespace}
  selector:
    matchLabels:
      app: dynamo-vllm-frontend
  endpoints:
  - port: metrics
    path: /metrics
    interval: ${metrics_interval}
