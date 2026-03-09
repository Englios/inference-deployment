#!/usr/bin/env python3

import argparse
import json
import time
import urllib.request


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


def benchmark(
    base_url: str, api_key: str, model: str, prompt: str, max_tokens: int
) -> dict:
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
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
    completion_tokens = None

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
                completion_tokens = usage.get("completion_tokens")

    if finished is None:
        finished = time.perf_counter()

    ttft = None if first_token_at is None else first_token_at - started
    total_time = finished - started
    generation_time = None if first_token_at is None else finished - first_token_at
    tokens_per_second = None

    if completion_tokens and generation_time and generation_time > 0:
        tokens_per_second = completion_tokens / generation_time

    return {
        "model": model,
        "ttft_seconds": ttft,
        "total_time_seconds": total_time,
        "generation_time_seconds": generation_time,
        "completion_tokens": completion_tokens,
        "generation_tokens_per_second": tokens_per_second,
    }


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
    args = parser.parse_args()

    model = args.model or discover_model(args.base_url, args.api_key)
    result = benchmark(args.base_url, args.api_key, model, args.prompt, args.max_tokens)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
