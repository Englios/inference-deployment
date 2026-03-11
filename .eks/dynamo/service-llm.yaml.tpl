apiVersion: v1
kind: Service
metadata:
  name: llm-service
  namespace: ${namespace}
  labels:
    app: dynamo-vllm-frontend
    inference.lane: dynamo-vllm
spec:
  type: ClusterIP
  selector:
    nvidia.com/dynamo-graph-deployment-name: ${dynamo_graph_name}
    nvidia.com/dynamo-component-type: frontend
  ports:
  - name: http
    port: 80
    targetPort: ${http_port}
  - name: metrics
    port: ${metrics_port}
    targetPort: ${metrics_port}
