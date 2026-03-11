#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path
from string import Template


def load_config(path: Path) -> dict:
    return json.loads(path.read_text())


def get_value(config: dict, dotted_path: str):
    value = config
    for part in dotted_path.split("."):
        value = value[part]
    return value


def flatten(config: dict) -> dict[str, str]:
    model = config["model"]
    engine = config["engine"]
    runtime = config["runtime"]
    ray = config["ray"]
    scheduling = config["scheduling"]
    dynamo = config["dynamo"]

    return {
        "namespace": str(config["namespace"]),
        "model_id": str(model["id"]),
        "model_source": str(model["source"]),
        "served_model_name": str(model["served_name"]),
        "engine_framework": str(engine["framework"]),
        "engine_name": str(engine.get("name", engine["framework"])),
        "tensor_parallel_size": str(engine["tensor_parallel_size"]),
        "pipeline_parallel_size": str(engine["pipeline_parallel_size"]),
        "data_parallel_size": str(engine["data_parallel_size"]),
        "max_model_len": str(engine["max_model_len"]),
        "gpu_memory_utilization": str(engine["gpu_memory_utilization"]),
        "transformers_version": str(engine["transformers_version"]),
        "vllm_allreduce_use_symm_mem": str(engine["vllm_allreduce_use_symm_mem"]),
        "block_size": str(engine["block_size"]),
        "max_num_seqs": str(engine["max_num_seqs"]),
        "http_port": str(runtime["http_port"]),
        "metrics_port": str(runtime["metrics_port"]),
        "metrics_interval": str(runtime["metrics_interval"]),
        "prometheus_host": str(runtime.get("prometheus_host", "")),
        "grafana_host": str(runtime.get("grafana_host", "")),
        "grafana_iframe_host": str(runtime.get("grafana_iframe_host", "")),
        "ray_service_name": str(ray["service_name"]),
        "ray_version": str(ray["ray_version"]),
        "ray_image": str(ray["image"]),
        "ray_dashboard_port": str(ray["dashboard_port"]),
        "ray_gcs_port": str(ray["gcs_port"]),
        "ray_client_port": str(ray["client_port"]),
        "ray_serve_min_replicas": str(ray["serve_min_replicas"]),
        "ray_serve_max_replicas": str(ray["serve_max_replicas"]),
        "ray_head_gpus": str(ray["head"]["gpus"]),
        "ray_head_cpu_request": str(ray["head"]["cpu_request"]),
        "ray_head_cpu_limit": str(ray["head"]["cpu_limit"]),
        "ray_head_memory_request": str(ray["head"]["memory_request"]),
        "ray_head_memory_limit": str(ray["head"]["memory_limit"]),
        "ray_worker_replicas": str(ray["worker"]["replicas"]),
        "ray_worker_min_replicas": str(ray["worker"]["min_replicas"]),
        "ray_worker_max_replicas": str(ray["worker"]["max_replicas"]),
        "ray_worker_hosts": str(ray["worker"]["hosts"]),
        "ray_worker_gpus": str(ray["worker"]["gpus"]),
        "ray_worker_cpu_request": str(ray["worker"]["cpu_request"]),
        "ray_worker_cpu_limit": str(ray["worker"]["cpu_limit"]),
        "ray_worker_memory_request": str(ray["worker"]["memory_request"]),
        "ray_worker_memory_limit": str(ray["worker"]["memory_limit"]),
        "ray_target_ongoing_requests": str(
            ray["autoscaling"]["target_ongoing_requests"]
        ),
        "ray_max_ongoing_requests": str(ray["autoscaling"]["max_ongoing_requests"]),
        "ray_health_check_period_s": str(ray["autoscaling"]["health_check_period_s"]),
        "ray_health_check_timeout_s": str(ray["autoscaling"]["health_check_timeout_s"]),
        "ray_graceful_shutdown_timeout_s": str(
            ray["autoscaling"]["graceful_shutdown_timeout_s"]
        ),
        "ray_graceful_shutdown_wait_loop_s": str(
            ray["autoscaling"]["graceful_shutdown_wait_loop_s"]
        ),
        "accelerator_label": str(scheduling["accelerator_label"]),
        "workload_label": str(scheduling["workload_label"]),
        "dedicated_taint_key": str(scheduling["dedicated_taint_key"]),
        "dedicated_taint_value": str(scheduling["dedicated_taint_value"]),
        "dynamo_graph_name": str(dynamo["graph_name"]),
        "dynamo_deployment_mode": str(dynamo.get("deployment_mode", "agg")),
        "dynamo_frontend_replicas": str(dynamo["frontend_replicas"]),
        "dynamo_worker_replicas": str(dynamo["worker_replicas"]),
        "dynamo_image": str(dynamo["image"]),
        "dynamo_model_cache_pvc": str(dynamo["model_cache_pvc"]),
        "dynamo_worker_gpu_count": str(dynamo["worker_gpu_count"]),
        "dynamo_worker_cpu_request": str(dynamo["worker_cpu_request"]),
        "dynamo_worker_cpu_limit": str(dynamo["worker_cpu_limit"]),
        "dynamo_worker_memory_request": str(dynamo["worker_memory_request"]),
        "dynamo_worker_memory_limit": str(dynamo["worker_memory_limit"]),
        "dynamo_worker_shared_memory": str(dynamo["worker_shared_memory"]),
    }


def render(config_path: Path, lane: str, output_root: Path) -> list[Path]:
    config = load_config(config_path)
    mapping = flatten(config)
    repo_root = config_path.parent.parent

    templates = {
        "ray-vllm": [
            (
                repo_root / ".eks" / "ray" / "ray-vllm-service.yaml.tpl",
                output_root / "ray" / "ray-vllm-service.yaml",
            ),
        ],
        "dynamo-vllm": [
            (
                repo_root / ".eks" / "dynamo" / "namespace.yaml.tpl",
                output_root / "dynamo" / "namespace.yaml",
            ),
            (
                repo_root / ".eks" / "dynamo" / "model-cache-pvc.yaml.tpl",
                output_root / "dynamo" / "model-cache-pvc.yaml",
            ),
            (
                repo_root / ".eks" / "dynamo" / "vllm" / "agg.yaml.tpl",
                output_root / "dynamo" / "vllm" / "agg.yaml",
            ),
            (
                repo_root / ".eks" / "dynamo" / "service-llm.yaml.tpl",
                output_root / "dynamo" / "service-llm.yaml",
            ),
            (
                repo_root
                / ".eks"
                / "monitoring"
                / "dynamo-frontend-podmonitor.yaml.tpl",
                output_root / "monitoring" / "dynamo-frontend-podmonitor.yaml",
            ),
            (
                repo_root / ".eks" / "monitoring" / "dynamo-worker-podmonitor.yaml.tpl",
                output_root / "monitoring" / "dynamo-worker-podmonitor.yaml",
            ),
            (
                repo_root
                / ".eks"
                / "monitoring"
                / "dynamo-llm-servicemonitor.yaml.tpl",
                output_root / "monitoring" / "dynamo-llm-servicemonitor.yaml",
            ),
        ],
    }

    outputs: list[Path] = []
    for template_path, output_path in templates[lane]:
        rendered = Template(template_path.read_text()).substitute(mapping)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered)
        outputs.append(output_path)
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--get")
    parser.add_argument("--lane", choices=["ray-vllm", "dynamo-vllm"])
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()

    config = load_config(args.config)
    if args.get:
        value = get_value(config, args.get)
        print(value)
        return

    if not args.lane or not args.output_root:
        raise SystemExit("--lane and --output-root are required when rendering")

    outputs = render(args.config, args.lane, args.output_root)
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
