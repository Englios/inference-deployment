#!/usr/bin/env python3

import argparse
import concurrent.futures
import json
import math
import time
import urllib.request


LONG_CONTEXT_PROMPT = " ".join(
    [
        "This is a long-context stress paragraph about distributed inference, scheduling, KV cache pressure, batch shaping, tensor parallel communication, and GPU memory residency."
    ]
    * 256
)


DEFAULT_TASK_SUITE = [
    {
        "name": "reasoning",
        "prompt": "A cluster has 2 nodes with 2 GPUs each. Explain how tensor parallelism 2 and pipeline parallelism 2 split one model across the hardware, and list two failure modes to watch for.",
        "max_tokens": 1024,
    },
    {
        "name": "summarization",
        "prompt": "Summarize the main tradeoffs between higher context length, higher concurrency, and GPU memory pressure in vLLM. Keep the answer concise and operational.",
        "max_tokens": 896,
    },
    {
        "name": "structured_extraction",
        "prompt": "Return JSON with keys cluster_goal, gpu_count, node_count, tensor_parallel_size, pipeline_parallel_size, and risks for this setup: one Qwen 122B-A10B model on 2 nodes with 2 GPUs each using TP=2 and PP=2.",
        "max_tokens": 768,
    },
    {
        "name": "code_generation",
        "prompt": "Write a short Python function that estimates total output tokens per second for a cluster given per-GPU output throughput and GPU count, then explain one limitation of that estimate.",
        "max_tokens": 1024,
    },
    {
        "name": "transformer_architecture",
        "prompt": "Describe the main components of a transformer architecture, explain the high-level flow from input tokens to output logits, and point out where attention and feed-forward blocks appear and what role each plays.",
        "max_tokens": 896,
    },
    {
        "name": "long_context_stress",
        "prompt": LONG_CONTEXT_PROMPT,
        "max_tokens": 768,
    },
    {
        "name": "long_generation_stress",
        "prompt": "Generate a detailed, operationally useful runbook for debugging throughput collapse in a multi-GPU inference cluster. Include sections for symptoms, likely causes, immediate checks, Prometheus/Grafana indicators, GPU/network failure signals, scaling decisions, and rollback strategy.",
        "max_tokens": 1536,
    },
]


def http_json(url: str, api_key: str | None = None) -> dict:
    request = urllib.request.Request(url)
    request.add_header("Content-Type", "application/json")
    if api_key:
        request.add_header("Authorization", f"Bearer {api_key}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


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


def empty_metric_summary() -> dict[str, float | None]:
    return {
        "latest": None,
        "max": None,
        "avg": None,
    }


def skipped_result(model: str, worker_nodes: int | None, worker_gpus: int | None, error: str) -> dict:
    """Return a zeroed-out result dict for a task that could not be run."""
    result: dict = {
        "model": model,
        "skipped": True,
        "skip_error": error,
        "ttft_seconds": None,
        "total_time_seconds": None,
        "generation_time_seconds": None,
        "prompt_tokens": None,
        "estimated_prompt_tokens": None,
        "effective_prompt_tokens": None,
        "completion_tokens": None,
        "input_tokens_per_second": None,
        "generation_tokens_per_second": None,
        "total_tokens_per_second": None,
        "worker_node_count": worker_nodes,
        "worker_gpu_count": worker_gpus,
        "estimated_per_node_output_tokens_per_second": None,
        "estimated_per_gpu_output_tokens_per_second": None,
        "kv_cache_metrics": {
            "kv_cache_usage_percent": empty_metric_summary(),
            "gpu_cache_usage_percent": empty_metric_summary(),
            "cpu_cache_usage_percent": empty_metric_summary(),
        },
        "queue_pressure_metrics": {
            "requests_running": empty_metric_summary(),
            "requests_waiting": empty_metric_summary(),
        },
    }
    result["summary_text"] = f"Skipped: {error}"
    return result


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
    metrics_url: str,
    api_key: str,
    model: str,
    prompt: str,
    max_tokens: int,
    worker_nodes: int | None = None,
    worker_gpus: int | None = None,
    messages: list[dict] | None = None,
) -> dict:
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
        pass

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
        "kv_cache_usage_percent": empty_metric_summary(),
        "gpu_cache_usage_percent": empty_metric_summary(),
        "cpu_cache_usage_percent": empty_metric_summary(),
    }

    queue_pressure_metrics = {
        "requests_running": empty_metric_summary(),
        "requests_waiting": empty_metric_summary(),
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
    metrics_url: str,
    api_key: str,
    model: str,
    worker_nodes: int | None = None,
    worker_gpus: int | None = None,
    rounds: int = 1,
    concurrency: int = 1,
) -> dict:
    task_results = []
    expanded_tasks: list[tuple[int, dict]] = []
    for round_index in range(rounds):
        for task in DEFAULT_TASK_SUITE:
            expanded_tasks.append((round_index + 1, task))

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, concurrency)
    ) as executor:
        future_map = {
            executor.submit(
                benchmark,
                base_url,
                metrics_url,
                api_key,
                model,
                task.get("prompt", ""),
                int(task["max_tokens"]),
                worker_nodes,
                worker_gpus,
                task.get("messages"),
            ): (round_number, task)
            for round_number, task in expanded_tasks
        }

        for future in concurrent.futures.as_completed(future_map):
            round_number, task = future_map[future]
            try:
                result = future.result()
            except Exception as exc:
                print(
                    f"  [WARN] task '{task['name']}' round {round_number} skipped: {exc}",
                    flush=True,
                )
                result = skipped_result(model, worker_nodes, worker_gpus, str(exc))
            task_results.append(
                {
                    "name": task["name"],
                    "round": round_number,
                    "max_tokens": task["max_tokens"],
                    "input_type": "messages" if task.get("messages") else "prompt",
                    "estimated_input_tokens": estimate_message_tokens(
                        task.get("messages")
                        or [{"role": "user", "content": task.get("prompt", "")}]
                    ),
                    "result": result,
                }
            )

    task_results.sort(key=lambda item: (item["round"], item["name"]))

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
        "rounds": rounds,
        "concurrency": concurrency,
        "summary": summary,
        "tasks": task_results,
    }
    result["summary_text"] = build_task_suite_summary(summary)
    return result


def run_repeated_prompt_benchmark(
    base_url: str,
    metrics_url: str,
    api_key: str,
    model: str,
    prompt: str,
    max_tokens: int,
    worker_nodes: int | None = None,
    worker_gpus: int | None = None,
    rounds: int = 1,
    concurrency: int = 1,
) -> dict:
    run_results = []

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=max(1, concurrency)
    ) as executor:
        futures = [
            executor.submit(
                benchmark,
                base_url,
                metrics_url,
                api_key,
                model,
                prompt,
                max_tokens,
                worker_nodes,
                worker_gpus,
                None,
            )
            for _ in range(rounds)
        ]

        for idx, future in enumerate(concurrent.futures.as_completed(futures), start=1):
            try:
                result = future.result()
            except Exception as exc:
                print(f"  [WARN] round {idx} skipped: {exc}", flush=True)
                result = skipped_result(model, worker_nodes, worker_gpus, str(exc))
            run_results.append({"round": idx, "result": result})

    summary = {
        "task_count": len(run_results),
        "avg_ttft_seconds": average(
            [item["result"]["ttft_seconds"] for item in run_results]
        ),
        "avg_total_time_seconds": average(
            [item["result"]["total_time_seconds"] for item in run_results]
        ),
        "avg_input_tokens_per_second": average(
            [item["result"]["input_tokens_per_second"] for item in run_results]
        ),
        "avg_generation_tokens_per_second": average(
            [item["result"]["generation_tokens_per_second"] for item in run_results]
        ),
        "avg_total_tokens_per_second": average(
            [item["result"]["total_tokens_per_second"] for item in run_results]
        ),
        "max_kv_cache_usage_percent": maximum(
            [
                item["result"]["kv_cache_metrics"]["kv_cache_usage_percent"]["max"]
                for item in run_results
            ]
        ),
        "avg_kv_cache_usage_percent": average(
            [
                item["result"]["kv_cache_metrics"]["kv_cache_usage_percent"]["avg"]
                for item in run_results
            ]
        ),
        "max_requests_waiting": maximum(
            [
                item["result"]["queue_pressure_metrics"]["requests_waiting"]["max"]
                for item in run_results
            ]
        ),
        "avg_requests_waiting": average(
            [
                item["result"]["queue_pressure_metrics"]["requests_waiting"]["avg"]
                for item in run_results
            ]
        ),
        "avg_requests_running": average(
            [
                item["result"]["queue_pressure_metrics"]["requests_running"]["avg"]
                for item in run_results
            ]
        ),
    }

    result = {
        "mode": "repeated_prompt",
        "model": model,
        "rounds": rounds,
        "concurrency": concurrency,
        "summary": summary,
        "runs": run_results,
    }
    result["summary_text"] = build_task_suite_summary(summary)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Benchmark TTFT and generation speed for a vLLM endpoint."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:18000")
    parser.add_argument("--metrics-url")
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model")
    parser.add_argument(
        "--prompt",
        default="Explain tensor parallelism and why TTFT matters for user experience.",
    )
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--worker-nodes", type=int)
    parser.add_argument("--worker-gpus", type=int)
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument(
        "--task-suite",
        action="store_true",
        help="Run the built-in benchmark task suite instead of a single prompt.",
    )
    args = parser.parse_args()

    model = args.model or discover_model(args.base_url, args.api_key)
    metrics_url = args.metrics_url or f"{args.base_url}/metrics"
    if args.task_suite:
        result = run_task_suite(
            args.base_url,
            metrics_url,
            args.api_key,
            model,
            worker_nodes=args.worker_nodes,
            worker_gpus=args.worker_gpus,
            rounds=args.rounds,
            concurrency=args.concurrency,
        )
    else:
        result = run_repeated_prompt_benchmark(
            args.base_url,
            metrics_url,
            args.api_key,
            model,
            args.prompt,
            args.max_tokens,
            worker_nodes=args.worker_nodes,
            worker_gpus=args.worker_gpus,
            rounds=args.rounds,
            concurrency=args.concurrency,
        )
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
