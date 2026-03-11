#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path


def load_window(
    window_file: str | None, default_range_seconds: int
) -> tuple[float, float]:
    if window_file:
        path = Path(window_file)
        if path.exists():
            payload = json.loads(path.read_text())
            return float(payload["start_time_unix"]), float(payload["end_time_unix"])
    end = time.time()
    return end - default_range_seconds, end


def fetch_json(
    base_url: str, query: str, start: float, end: float, step_seconds: int
) -> dict:
    params = urllib.parse.urlencode(
        {
            "query": query,
            "start": f"{start:.3f}",
            "end": f"{end:.3f}",
            "step": str(step_seconds),
        }
    )
    url = f"{base_url}/api/v1/query_range?{params}"
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.loads(response.read().decode())


def summarize(series: list[dict[str, float]]) -> dict[str, float | None]:
    if not series:
        return {"latest": None, "min": None, "max": None, "avg": None}
    values = [point["value"] for point in series]
    return {
        "latest": values[-1],
        "min": min(values),
        "max": max(values),
        "avg": sum(values) / len(values),
    }


def normalize_result(
    payload: dict, series_name: str
) -> dict[str, list[dict[str, float]]]:
    result = payload.get("data", {}).get("result", [])
    if not result:
        return {}

    normalized: dict[str, list[dict[str, float]]] = {}
    for item in result:
        metric = item.get("metric", {})
        suffix = ""
        for label_key in ("Hostname", "instance", "node", "kubernetes_node"):
            label_value = metric.get(label_key)
            if label_value:
                suffix = f"::{label_value}"
                break
        values = item.get("values", [])
        normalized[f"{series_name}{suffix}"] = [
            {"timestamp": float(timestamp), "value": float(value)}
            for timestamp, value in values
            if value not in {"NaN", "Inf", "-Inf"}
        ]
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export Prometheus range query data for a benchmark window."
    )
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--window-file")
    parser.add_argument("--default-range-seconds", type=int, default=300)
    parser.add_argument("--step-seconds", type=int, default=5)
    parser.add_argument("--query", action="append", default=[])
    args = parser.parse_args()

    start, end = load_window(args.window_file, args.default_range_seconds)
    output = {
        "window": {
            "start_time_unix": start,
            "end_time_unix": end,
            "duration_seconds": max(0.0, end - start),
            "step_seconds": args.step_seconds,
        },
        "series": {},
        "summary": {},
    }

    for item in args.query:
        name, query = item.split("=", 1)
        normalized_series = normalize_result(
            fetch_json(args.base_url, query, start, end, args.step_seconds), name
        )
        for resolved_name, series in normalized_series.items():
            output["series"][resolved_name] = series
            output["summary"][resolved_name] = summarize(series)

    print(json.dumps(output, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
