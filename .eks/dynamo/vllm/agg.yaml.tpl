# NIXL Integration Point:
#   For disaggregated prefill/decode setups, add --kv-transfer-config to worker args.
#   Example (Prefill): --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_producer"}'
#   Example (Decode): --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_consumer"}'
#   See disagg.yaml.tpl for full disaggregated template scaffold.
#
# KV-Routing Integration Point:
#   Dynamo supports KV-aware routing in Frontend to route prefill vs decode requests.
#   This is configured via DynamoGraphDeployment spec.routing (not yet wired in this template).
#   When enabled, Frontend routes based on request type to appropriate worker pools.
#
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  name: ${dynamo_graph_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: dynamo-vllm
    app.kubernetes.io/part-of: inference-engine
    inference.engine: ${engine_framework}
    inference.lane: dynamo-vllm
spec:
  backendFramework: ${engine_framework}
  pvcs:
  - name: ${dynamo_model_cache_pvc}
    create: false
  envs:
  - name: HF_HOME
    value: /opt/models
  services:
    Frontend:
      serviceName: frontend
      componentType: frontend
      replicas: ${dynamo_frontend_replicas}
      labels:
        app.kubernetes.io/name: dynamo-vllm
        app.kubernetes.io/component: frontend
        inference.lane: dynamo-vllm
      envs:
      - name: DYN_LOGGING_JSONL
        value: "1"
      - name: DYN_SYSTEM_PORT
        value: "${metrics_port}"
      volumeMounts:
      - name: ${dynamo_model_cache_pvc}
        mountPoint: /opt/models
      extraPodSpec:
        mainContainer:
          image: ${dynamo_image}
          workingDir: /workspace/examples/backends/vllm
          ports:
          - containerPort: ${http_port}
            name: http
          - containerPort: ${metrics_port}
            name: metrics
          readinessProbe:
            httpGet:
              path: /v1/models
              port: ${http_port}
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: ${http_port}
            periodSeconds: 20
            timeoutSeconds: 5
    VllmWorker:
      serviceName: worker
      componentType: worker
      replicas: ${dynamo_worker_replicas}
      envFromSecret: hf-token-secret
      labels:
        app.kubernetes.io/name: dynamo-vllm
        app.kubernetes.io/component: worker
        inference.lane: dynamo-vllm
      envs:
      - name: DYN_LOGGING_JSONL
        value: "1"
      - name: DYN_SYSTEM_PORT
        value: "${metrics_port}"
      - name: MODEL_PATH
        value: ${model_source}
      - name: SERVED_MODEL_NAME
        value: ${served_model_name}
      sharedMemory:
        size: ${dynamo_worker_shared_memory}
      volumeMounts:
      - name: ${dynamo_model_cache_pvc}
        mountPoint: /opt/models
      extraPodSpec:
        nodeSelector:
          accelerator: ${accelerator_label}
          workload: ${workload_label}
        mainContainer:
          image: ${dynamo_image}
          workingDir: /workspace/examples/backends/vllm
          command:
          - /bin/sh
          - -c
          args:
          - >-
            python3 -m dynamo.vllm
            --model $$MODEL_PATH
            --served-model-name $$SERVED_MODEL_NAME
            --tensor-parallel-size ${tensor_parallel_size}
            --pipeline-parallel-size ${pipeline_parallel_size}
            --data-parallel-size ${data_parallel_size}
            --gpu-memory-utilization ${gpu_memory_utilization}
            --max-model-len ${max_model_len}
            --block-size ${block_size}
            --max-num-seqs ${max_num_seqs}
          ports:
          - containerPort: ${metrics_port}
            name: metrics
          resources:
            requests:
              gpu: "${dynamo_worker_gpu_count}"
              cpu: "${dynamo_worker_cpu_request}"
              memory: ${dynamo_worker_memory_request}
            limits:
              gpu: "${dynamo_worker_gpu_count}"
              cpu: "${dynamo_worker_cpu_limit}"
              memory: ${dynamo_worker_memory_limit}
