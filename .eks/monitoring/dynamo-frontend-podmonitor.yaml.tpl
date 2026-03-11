apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: dynamo-frontend
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - ${namespace}
  selector:
    matchLabels:
      nvidia.com/dynamo-component-type: frontend
      nvidia.com/dynamo-graph-deployment-name: ${dynamo_graph_name}
  podMetricsEndpoints:
  - port: metrics
    path: /metrics
    interval: ${metrics_interval}
