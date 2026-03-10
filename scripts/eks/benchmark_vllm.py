#!/usr/bin/env python3

import argparse
import json
import math
import threading
import time
import urllib.request


DEFAULT_TASK_SUITE = [
    {
        "name": "reasoning",
        "prompt": "A cluster has 2 nodes with 2 GPUs each. Explain how tensor parallelism 2 and pipeline parallelism 2 split one model across the hardware, and list two failure modes to watch for.",
        "max_tokens": 768,
    },
    {
        "name": "summarization",
        "prompt": "Summarize the main tradeoffs between higher context length, higher concurrency, and GPU memory pressure in vLLM. Keep the answer concise and operational.",
        "max_tokens": 640,
    },
    {
        "name": "structured_extraction",
        "prompt": "Return JSON with keys cluster_goal, gpu_count, node_count, tensor_parallel_size, pipeline_parallel_size, and risks for this setup: one Qwen 122B-A10B model on 2 nodes with 2 GPUs each using TP=2 and PP=2.",
        "max_tokens": 512,
    },
    {
        "name": "code_generation",
        "prompt": "Write a short Python function that estimates total output tokens per second for a cluster given per-GPU output throughput and GPU count, then explain one limitation of that estimate.",
        "max_tokens": 768,
    },
    {
        "name": "multimodal_transformer_diagram",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": "https://deeprevision.github.io/posts/001-transformer/transformer.png"
                        },
                    },
                    {
                        "type": "text",
                        "text": "Describe the main parts of this transformer diagram, explain the high-level flow from input to output, and point out where attention and feed-forward blocks appear.",
                    },
                ],
            }
        ],
        "max_tokens": 768,
    },
]


def http_json(url: str, api_key: str | None = None) -> dict:
    request = urllib.request.Request(url)
    request.add_header("Content-Type", "application/json")
    if api_key:
        request.add_header("Authorization", f"Bearer {api_key}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


def http_text(url: str, api_key: str | None = None) -> str:
    request = urllib.request.Request(url)
    if api_key:
        request.add_header("Authorization", f"Bearer {api_key}")
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.read().decode()


def discover_model(base_url: str, api_key: str) -> str:
    payload = http_json(f"{base_url}/v1/models", api_key)
    return payload["data"][0]["id"]


def estimate_token_count(text: str) -> int:
    stripped = text.strip()
    if not stripped:
        return 0

    words = len(stripped.split())
    chars = len(stripped)
    return max(words, math.ceil(chars / 4))


def estimate_message_tokens(messages: list[dict]) -> int:
    total = 0

    for message in messages:
        content = message.get("content", "")
        if isinstance(content, str):
            total += estimate_token_count(content)
            continue

        if isinstance(content, list):
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "text":
                    total += estimate_token_count(item.get("text", ""))

    return total


def collect_metric_values(
    metrics_text: str, metric_names: list[str]
) -> dict[str, list[float]]:
    collected = {metric_name: [] for metric_name in metric_names}

    for raw_line in metrics_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        metric_name = line.split("{", 1)[0].split(" ", 1)[0]
        if metric_name not in collected:
            continue

        try:
            value = float(line.rsplit(" ", 1)[1])
        except (IndexError, ValueError):
            continue

        collected[metric_name].append(value)

    return collected


def summarize_metric_samples(samples: list[float]) -> dict[str, float | None]:
    if not samples:
        return {
            "latest": None,
            "max": None,
            "avg": None,
        }

    latest = samples[-1]
    peak = max(samples)
    average = sum(samples) / len(samples)

    if peak <= 1.0:
        latest *= 100
        peak *= 100
        average *= 100

    return {
        "latest": latest,
        "max": peak,
        "avg": average,
    }


def sample_metrics(
    base_url: str,
    api_key: str,
    stop_event: threading.Event,
    metric_names: list[str],
    interval_seconds: float = 1.0,
) -> dict[str, list[float]]:
    metric_samples = {metric_name: [] for metric_name in metric_names}

    while not stop_event.is_set():
        try:
            metrics_text = http_text(f"{base_url}/metrics", api_key)
            scrape = collect_metric_values(metrics_text, metric_names)
            for metric_name, values in scrape.items():
                if values:
                    metric_samples[metric_name].append(max(values))
        except Exception:
            pass

        stop_event.wait(interval_seconds)

    return metric_samples


def average(values: list[float | None]) -> float | None:
    valid_values = [value for value in values if value is not None]
    if not valid_values:
        return None
    return sum(valid_values) / len(valid_values)


def maximum(values: list[float | None]) -> float | None:
    valid_values = [value for value in values if value is not None]
    if not valid_values:
        return None
    return max(valid_values)


def format_metric(value: float | None, suffix: str = "") -> str:
    if value is None:
        return "n/a"
    return f"{value:.2f}{suffix}"


def build_single_run_summary(result: dict) -> str:
    return (
        "Single run summary: "
        f"TTFT {format_metric(result.get('ttft_seconds'), 's')}, "
        f"generation throughput {format_metric(result.get('generation_tokens_per_second'), ' tok/s')}, "
        f"total throughput {format_metric(result.get('total_tokens_per_second'), ' tok/s')}, "
        f"KV cache avg {format_metric(result['kv_cache_metrics']['kv_cache_usage_percent']['avg'], '%')}, "
        f"KV cache peak {format_metric(result['kv_cache_metrics']['kv_cache_usage_percent']['max'], '%')}, "
        f"queue waiting avg {format_metric(result['queue_pressure_metrics']['requests_waiting']['avg'])}, "
        f"queue waiting peak {format_metric(result['queue_pressure_metrics']['requests_waiting']['max'])}."
    )


def build_task_suite_summary(summary: dict) -> str:
    return (
        f"Task suite summary across {summary['task_count']} tasks: "
        f"avg TTFT {format_metric(summary.get('avg_ttft_seconds'), 's')}, "
        f"avg generation throughput {format_metric(summary.get('avg_generation_tokens_per_second'), ' tok/s')}, "
        f"avg total throughput {format_metric(summary.get('avg_total_tokens_per_second'), ' tok/s')}, "
        f"KV cache avg {format_metric(summary.get('avg_kv_cache_usage_percent'), '%')}, "
        f"KV cache peak {format_metric(summary.get('max_kv_cache_usage_percent'), '%')}, "
        f"avg running requests {format_metric(summary.get('avg_requests_running'))}, "
        f"avg waiting requests {format_metric(summary.get('avg_requests_waiting'))}, "
        f"peak waiting requests {format_metric(summary.get('max_requests_waiting'))}."
    )


def benchmark(
    base_url: str,
    api_key: str,
    model: str,
    prompt: str,
    max_tokens: int,
    worker_nodes: int | None = None,
    worker_gpus: int | None = None,
    messages: list[dict] | None = None,
) -> dict:
    kv_metric_names = [
        "vllm:kv_cache_usage_perc",
        "vllm:gpu_cache_usage_perc",
        "vllm:cpu_cache_usage_perc",
        "vllm:num_requests_running",
        "vllm:num_requests_waiting",
    ]
    body = json.dumps(
        {
            "model": model,
            "messages": messages or [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": 0,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
    ).encode()

    request = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )

    started = time.perf_counter()
    first_token_at = None
    finished = None
    prompt_tokens = None
    completion_tokens = None
    metrics_stop_event = threading.Event()
    sampled_metrics: dict[str, list[float]] = {}

    def sampler() -> None:
        nonlocal sampled_metrics
        sampled_metrics = sample_metrics(
            base_url,
            api_key,
            metrics_stop_event,
            kv_metric_names,
        )

    sampler_thread = threading.Thread(target=sampler, daemon=True)
    sampler_thread.start()

    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8").strip()
                if not line.startswith("data: "):
                    continue
                payload = line[6:]
                if payload == "[DONE]":
                    finished = time.perf_counter()
                    break

                event = json.loads(payload)
                choices = event.get("choices", [])
                if choices:
                    delta = choices[0].get("delta", {})
                    if first_token_at is None and (
                        delta.get("content") or delta.get("reasoning_content")
                    ):
                        first_token_at = time.perf_counter()

                usage = event.get("usage")
                if usage:
                    prompt_tokens = usage.get("prompt_tokens")
                    completion_tokens = usage.get("completion_tokens")
    finally:
        metrics_stop_event.set()
        sampler_thread.join(timeout=2)

    if finished is None:
        finished = time.perf_counter()

    ttft = None if first_token_at is None else first_token_at - started
    total_time = finished - started
    generation_time = None if first_token_at is None else finished - first_token_at
    effective_prompt_tokens = prompt_tokens or estimate_message_tokens(
        messages or [{"role": "user", "content": prompt}]
    )
    input_tokens_per_second = None
    output_tokens_per_second = None
    total_tokens_per_second = None
    estimated_per_node_output_tokens_per_second = None
    estimated_per_gpu_output_tokens_per_second = None

    if total_time > 0:
        input_tokens_per_second = effective_prompt_tokens / total_time

    if completion_tokens and generation_time and generation_time > 0:
        output_tokens_per_second = completion_tokens / generation_time

    if completion_tokens and total_time > 0:
        total_tokens_per_second = (
            effective_prompt_tokens + completion_tokens
        ) / total_time

    if output_tokens_per_second and worker_nodes and worker_nodes > 0:
        estimated_per_node_output_tokens_per_second = (
            output_tokens_per_second / worker_nodes
        )

    if output_tokens_per_second and worker_gpus and worker_gpus > 0:
        estimated_per_gpu_output_tokens_per_second = (
            output_tokens_per_second / worker_gpus
        )

    kv_cache_metrics = {
        "kv_cache_usage_percent": summarize_metric_samples(
            sampled_metrics.get("vllm:kv_cache_usage_perc", [])
        ),
        "gpu_cache_usage_percent": summarize_metric_samples(
            sampled_metrics.get("vllm:gpu_cache_usage_perc", [])
        ),
        "cpu_cache_usage_percent": summarize_metric_samples(
            sampled_metrics.get("vllm:cpu_cache_usage_perc", [])
        ),
    }

    queue_pressure_metrics = {
        "requests_running": summarize_metric_samples(
            sampled_metrics.get("vllm:num_requests_running", [])
        ),
        "requests_waiting": summarize_metric_samples(
            sampled_metrics.get("vllm:num_requests_waiting", [])
        ),
    }

    result = {
        "model": model,
        "ttft_seconds": ttft,
        "total_time_seconds": total_time,
        "generation_time_seconds": generation_time,
        "prompt_tokens": prompt_tokens,
        "estimated_prompt_tokens": estimate_message_tokens(
            messages or [{"role": "user", "content": prompt}]
        ),
        "effective_prompt_tokens": effective_prompt_tokens,
        "completion_tokens": completion_tokens,
        "input_tokens_per_second": input_tokens_per_second,
        "generation_tokens_per_second": output_tokens_per_second,
        "total_tokens_per_second": total_tokens_per_second,
        "worker_node_count": worker_nodes,
        "worker_gpu_count": worker_gpus,
        "estimated_per_node_output_tokens_per_second": estimated_per_node_output_tokens_per_second,
        "estimated_per_gpu_output_tokens_per_second": estimated_per_gpu_output_tokens_per_second,
        "kv_cache_metrics": kv_cache_metrics,
        "queue_pressure_metrics": queue_pressure_metrics,
    }
    result["summary_text"] = build_single_run_summary(result)
    return result


def run_task_suite(
    base_url: str,
    api_key: str,
    model: str,
    worker_nodes: int | None = None,
    worker_gpus: int | None = None,
) -> dict:
    task_results = []

    for task in DEFAULT_TASK_SUITE:
        result = benchmark(
            base_url,
            api_key,
            model,
            task.get("prompt", ""),
            int(task["max_tokens"]),
            worker_nodes=worker_nodes,
            worker_gpus=worker_gpus,
            messages=task.get("messages"),
        )
        task_results.append(
            {
                "name": task["name"],
                "prompt": task.get("prompt"),
                "messages": task.get("messages"),
                "max_tokens": task["max_tokens"],
                "result": result,
            }
        )

    summary = {
        "task_count": len(task_results),
        "avg_ttft_seconds": average(
            [task_result["result"]["ttft_seconds"] for task_result in task_results]
        ),
        "avg_total_time_seconds": average(
            [
                task_result["result"]["total_time_seconds"]
                for task_result in task_results
            ]
        ),
        "avg_input_tokens_per_second": average(
            [
                task_result["result"]["input_tokens_per_second"]
                for task_result in task_results
            ]
        ),
        "avg_generation_tokens_per_second": average(
            [
                task_result["result"]["generation_tokens_per_second"]
                for task_result in task_results
            ]
        ),
        "avg_total_tokens_per_second": average(
            [
                task_result["result"]["total_tokens_per_second"]
                for task_result in task_results
            ]
        ),
        "max_kv_cache_usage_percent": maximum(
            [
                task_result["result"]["kv_cache_metrics"]["kv_cache_usage_percent"][
                    "max"
                ]
                for task_result in task_results
            ]
        ),
        "avg_kv_cache_usage_percent": average(
            [
                task_result["result"]["kv_cache_metrics"]["kv_cache_usage_percent"][
                    "avg"
                ]
                for task_result in task_results
            ]
        ),
        "max_requests_waiting": maximum(
            [
                task_result["result"]["queue_pressure_metrics"]["requests_waiting"][
                    "max"
                ]
                for task_result in task_results
            ]
        ),
        "avg_requests_waiting": average(
            [
                task_result["result"]["queue_pressure_metrics"]["requests_waiting"][
                    "avg"
                ]
                for task_result in task_results
            ]
        ),
        "avg_requests_running": average(
            [
                task_result["result"]["queue_pressure_metrics"]["requests_running"][
                    "avg"
                ]
                for task_result in task_results
            ]
        ),
    }

    result = {
        "mode": "task_suite",
        "suite_name": "default",
        "model": model,
        "worker_node_count": worker_nodes,
        "worker_gpu_count": worker_gpus,
        "summary": summary,
        "tasks": task_results,
    }
    result["summary_text"] = build_task_suite_summary(summary)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark TTFT and generation speed for a vLLM endpoint."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:18000")
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model")
    parser.add_argument(
        "--prompt",
        default="Explain tensor parallelism and why TTFT matters for user experience.",
    )
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--worker-nodes", type=int)
    parser.add_argument("--worker-gpus", type=int)
    parser.add_argument(
        "--task-suite",
        action="store_true",
        help="Run the built-in benchmark task suite instead of a single prompt.",
    )
    args = parser.parse_args()

    model = args.model or discover_model(args.base_url, args.api_key)
    if args.task_suite:
        result = run_task_suite(
            args.base_url,
            args.api_key,
            model,
            worker_nodes=args.worker_nodes,
            worker_gpus=args.worker_gpus,
        )
    else:
        result = benchmark(
            args.base_url,
            args.api_key,
            model,
            args.prompt,
            args.max_tokens,
            worker_nodes=args.worker_nodes,
            worker_gpus=args.worker_gpus,
        )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
