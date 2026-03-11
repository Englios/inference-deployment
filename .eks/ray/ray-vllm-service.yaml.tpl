apiVersion: ray.io/v1
kind: RayService
metadata:
  name: ${ray_service_name}
  namespace: ${namespace}
spec:
  serveConfigV2: |
    applications:
    - name: llms
      import_path: ray.serve.llm:build_openai_app
      route_prefix: "/"
      args:
        llm_configs:
        - model_loading_config:
            model_id: ${model_id}
            model_source: ${model_source}
          engine_kwargs:
            distributed_executor_backend: ray
            tensor_parallel_size: ${tensor_parallel_size}
            pipeline_parallel_size: ${pipeline_parallel_size}
            max_model_len: ${max_model_len}
            gpu_memory_utilization: ${gpu_memory_utilization}
          deployment_config:
            autoscaling_config:
              min_replicas: 1
              max_replicas: 1
              target_ongoing_requests: ${ray_target_ongoing_requests}
            max_ongoing_requests: ${ray_max_ongoing_requests}
            health_check_period_s: ${ray_health_check_period_s}
            health_check_timeout_s: ${ray_health_check_timeout_s}
            graceful_shutdown_timeout_s: ${ray_graceful_shutdown_timeout_s}
            graceful_shutdown_wait_loop_s: ${ray_graceful_shutdown_wait_loop_s}
      runtime_env:
        pip:
        - transformers==${transformers_version}
        env_vars:
          VLLM_ALLREDUCE_USE_SYMM_MEM: "${vllm_allreduce_use_symm_mem}"
  rayClusterConfig:
    rayVersion: "${ray_version}"
    headGroupSpec:
      rayStartParams:
        num-cpus: "${ray_head_cpu_request}"
        num-gpus: "${ray_head_gpus}"
      template:
        spec:
          nodeSelector:
            accelerator: ${accelerator_label}
            workload: ${workload_label}
          tolerations:
          - key: ${dedicated_taint_key}
            operator: Equal
            value: ${dedicated_taint_value}
            effect: NoSchedule
          containers:
          - name: ray-head
            image: ${ray_image}
            env:
            - name: RAY_PROMETHEUS_HOST
              value: ${prometheus_host}
            - name: RAY_GRAFANA_HOST
              value: ${grafana_host}
            - name: RAY_GRAFANA_IFRAME_HOST
              value: ${grafana_iframe_host}
            ports:
            - containerPort: ${http_port}
              name: serve
            - containerPort: ${ray_gcs_port}
              name: gcs
            - containerPort: ${ray_dashboard_port}
              name: dashboard
            - containerPort: 8080
              name: metrics
            - containerPort: ${ray_client_port}
              name: client
            resources:
              limits:
                cpu: "${ray_head_cpu_limit}"
                memory: ${ray_head_memory_limit}
                nvidia.com/gpu: "${ray_head_gpus}"
              requests:
                cpu: "${ray_head_cpu_request}"
                memory: ${ray_head_memory_request}
                nvidia.com/gpu: "${ray_head_gpus}"
    workerGroupSpecs:
    - groupName: gpu-workers
      replicas: ${ray_worker_replicas}
      minReplicas: ${ray_worker_min_replicas}
      maxReplicas: ${ray_worker_max_replicas}
      numOfHosts: ${ray_worker_hosts}
      rayStartParams:
        num-gpus: "${ray_worker_gpus}"
      template:
        spec:
          nodeSelector:
            accelerator: ${accelerator_label}
            workload: ${workload_label}
          tolerations:
          - key: ${dedicated_taint_key}
            operator: Equal
            value: ${dedicated_taint_value}
            effect: NoSchedule
          containers:
          - name: ray-worker
            image: ${ray_image}
            env:
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ray-vllm-secrets
                  key: HF_TOKEN
            resources:
              limits:
                cpu: "${ray_worker_cpu_limit}"
                memory: ${ray_worker_memory_limit}
                nvidia.com/gpu: "${ray_worker_gpus}"
              requests:
                cpu: "${ray_worker_cpu_request}"
                memory: ${ray_worker_memory_request}
                nvidia.com/gpu: "${ray_worker_gpus}"
