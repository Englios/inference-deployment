#!/usr/bin/env python3
"""Render experiment graphs from captured metrics and benchmark results."""

from __future__ import annotations

import json
import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

# ---------------------------------------------------------------------------
# Human-readable label maps
# ---------------------------------------------------------------------------

_METRIC_LABELS: dict[str, str] = {
    "gpu_util_pct": "GPU Utilization (%)",
    "gpu_mem_mb": "GPU Memory",
    "gpu_power_w": "GPU Power (W)",
    "gpu_temp_c": "GPU Temperature (°C)",
    "ray_ongoing_requests": "Ongoing Requests",
    "ray_queue_len": "Queue Length",
    "ray_http_rps": "HTTP Req/s",
    "ray_deployment_rps": "Deployment Req/s",
    "pod_rx_bps": "Pod RX",
    "pod_tx_bps": "Pod TX",
    "node_rx_bps": "Node RX (all)",
    "node_tx_bps": "Node TX (all)",
    "pod_drop_pps": "Dropped Packets/s",
}


def _pretty_metric(name: str) -> str:
    """Return a human-readable label for a metric key."""
    base = name.split("_by_node::")[0]
    return _METRIC_LABELS.get(base, base.replace("_", " ").title())


def _shorten_node(raw: str) -> str:
    """Shorten a full AWS hostname or IP:port to a compact node label.

    Examples:
        ip-10-42-100-91.us-west-2.compute.internal  ->  10.42.100.91
        10.42.100.91:9100                            ->  10.42.100.91
    """
    raw = raw.split(":")[0]
    if raw.startswith("ip-"):
        short = raw.split(".")[0]  # "ip-10-42-100-91"
        return short[3:].replace("-", ".")  # "10.42.100.91"
    return raw


def _parse_topology(topology_path: Path) -> dict[str, str]:
    """Parse topology.txt and return a mapping of short-IP -> role label.

    Returns e.g. {"10.42.101.100": "Head", "10.42.100.91": "Worker"}
    """
    if not topology_path.exists():
        return {}
    head_nodes: list[str] = []
    worker_nodes: list[str] = []
    current = None
    for line in topology_path.read_text().splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if "Ray head pod" in stripped:
            current = "head"
        elif "Ray worker pod" in stripped:
            current = "worker"
        elif stripped.startswith("==>"):
            # Any other ==> section (e.g. "Distinct nodes...") ends the sections
            current = None
        elif current in ("head", "worker"):
            parts = stripped.split()
            # Data rows look like: <pod-name>   <node-hostname>   <pod-ip>
            # Skip column-header rows (POD / NODE / IP) and any misc lines
            if len(parts) >= 2 and parts[0].startswith("ray-"):
                short = _shorten_node(parts[1])
                if current == "head":
                    head_nodes.append(short)
                else:
                    worker_nodes.append(short)
    role_map: dict[str, str] = {}
    for ip in head_nodes:
        role_map[ip] = "Head"
    for i, ip in enumerate(worker_nodes, 1):
        role_map[ip] = f"Worker {i}" if len(worker_nodes) > 1 else "Worker"
    return role_map


def _node_display(short_ip: str, role_map: dict[str, str]) -> str:
    """Return display label like 'Head (10.42.101.100)' or 'Worker (10.42.100.91)'."""
    role = role_map.get(short_ip)
    if role:
        return f"{role} ({short_ip})"
    return short_ip


# ---------------------------------------------------------------------------
# Data loading helpers
# ---------------------------------------------------------------------------


def _load_json(path: Path):
    if not path.exists():
        return None
    return json.loads(path.read_text())


def _human_rate_bytes(value: float) -> tuple[float, str]:
    if abs(value) >= 1024**3:
        return value / (1024**3), "GB/s"
    if abs(value) >= 1024**2:
        return value / (1024**2), "MB/s"
    if abs(value) >= 1024:
        return value / 1024, "KB/s"
    return value, "B/s"


def _human_bytes(value: float) -> tuple[float, str]:
    if abs(value) >= 1024**3:
        return value / (1024**3), "GB"
    if abs(value) >= 1024**2:
        return value / (1024**2), "MB"
    if abs(value) >= 1024:
        return value / 1024, "KB"
    return value, "B"


def _series_to_df(series_map: dict[str, list[dict]]) -> pd.DataFrame:
    """Flatten a series_map into a tidy DataFrame."""
    rows = []
    for metric_name, series in series_map.items():
        for point in series:
            rows.append({
                "metric_raw": metric_name,
                "timestamp": pd.to_datetime(point["timestamp"], unit="s"),
                "value": float(point["value"]),
            })
    return pd.DataFrame(rows)


def _split_per_node(
    df: pd.DataFrame,
    base_metric: str,
    role_map: dict[str, str] | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Return (aggregate_df, per_node_df) for a given base metric name.

    If role_map is provided, the 'node' column is labelled
    'Head (ip)' / 'Worker (ip)' instead of a bare IP.
    """
    per_node_pattern = base_metric + "_by_node::"
    agg = df[df["metric_raw"] == base_metric].copy()
    per = df[df["metric_raw"].str.startswith(per_node_pattern)].copy()
    if not per.empty:
        per["node"] = (
            per["metric_raw"]
            .str.replace(per_node_pattern, "", regex=False)
            .apply(_shorten_node)
        )
        if role_map:
            per["node"] = per["node"].apply(lambda n: _node_display(n, role_map))
    return agg, per


# ---------------------------------------------------------------------------
# Plot helpers
# ---------------------------------------------------------------------------


def _style_time_axis(ax):
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
    ax.tick_params(axis="x", rotation=40)
    ax.set_xlabel("Time", labelpad=8)


def _place_legend(ax, title: str | None = None):
    ax.legend(
        loc="upper left",
        bbox_to_anchor=(0.0, 1.0),
        ncol=2,
        framealpha=0.85,
        edgecolor="none",
        fontsize=11,
        title=title,
    )


def _save(fig: plt.Figure, path: Path):
    fig.savefig(path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def _add_bar_labels(ax, fmt="%.1f"):
    for container in ax.containers:
        ax.bar_label(container, fmt=fmt, padding=4, fontsize=10)


def _task_label(raw: str) -> str:
    return raw.replace("_", " ").title()


# ---------------------------------------------------------------------------
# Aggregate time-series
# ---------------------------------------------------------------------------


def _plot_aggregate(
    path: Path,
    title: str,
    df: pd.DataFrame,
    ylabel: str,
    hue_col: str = "label",
):
    """Simple single-panel time-series with pretty hue labels."""
    if df.empty:
        return
    fig, ax = plt.subplots(figsize=(11, 5))
    sns.lineplot(data=df, x="timestamp", y="value", hue=hue_col, linewidth=2.8, ax=ax)
    ax.set_title(title, pad=14)
    ax.set_ylabel(ylabel, labelpad=8)
    _style_time_axis(ax)
    n = df[hue_col].nunique()
    if n > 1:
        _place_legend(ax)
    elif ax.get_legend():
        ax.get_legend().remove()
    _save(fig, path)


# ---------------------------------------------------------------------------
# Per-node time-series (one file per metric, lines = nodes)
# ---------------------------------------------------------------------------


def _plot_per_node(
    path: Path,
    title: str,
    per_df: pd.DataFrame,
    ylabel: str,
    agg_df: pd.DataFrame | None = None,
):
    """Per-node lines on a single axis, with an optional dashed overall reference."""
    if per_df.empty:
        return
    fig, ax = plt.subplots(figsize=(11, 5))
    nodes = sorted(per_df["node"].unique())
    palette = sns.color_palette("deep", len(nodes))
    for color, node in zip(palette, nodes):
        nd = per_df[per_df["node"] == node]
        ax.plot(nd["timestamp"], nd["value"], linewidth=2.2, label=node, color=color)
    if agg_df is not None and not agg_df.empty:
        ax.plot(
            agg_df["timestamp"],
            agg_df["value"],
            linewidth=3.0,
            linestyle="--",
            color="#374151",
            label="Overall avg",
            alpha=0.7,
        )
    ax.set_title(title, pad=14)
    ax.set_ylabel(ylabel, labelpad=8)
    _style_time_axis(ax)
    _place_legend(ax, title="Node")
    _save(fig, path)


# ---------------------------------------------------------------------------
# GPU graphs
# ---------------------------------------------------------------------------


def _render_gpu(graphs_dir: Path, gpu_data: dict, role_map: dict[str, str] | None = None):
    raw_df = _series_to_df(gpu_data.get("series", {}))
    if raw_df.empty:
        return

    GPU_METRICS = [
        ("gpu_util_pct", "GPU Utilization",  "Percent (%)",  "gpu-utilization"),
        ("gpu_mem_mb",   "GPU Memory",        "Memory",       "gpu-memory"),
        ("gpu_power_w",  "GPU Power Draw",    "Watts (W)",    "gpu-power"),
        ("gpu_temp_c",   "GPU Temperature",   "Celsius (°C)", "gpu-temperature"),
    ]

    for base, title, ylabel, stem in GPU_METRICS:
        agg, per = _split_per_node(raw_df, base, role_map=role_map)

        # Convert memory bytes to human-readable
        if base == "gpu_mem_mb":
            if not agg.empty:
                converted = [_human_bytes(v * 1024 * 1024) for v in agg["value"]]
                agg = agg.copy()
                agg["value"] = [c[0] for c in converted]
                ylabel = converted[0][1]
            if not per.empty:
                converted = [_human_bytes(v * 1024 * 1024) for v in per["value"]]
                per = per.copy()
                per["value"] = [c[0] for c in converted]

        # Aggregate single-line plot
        agg_plot = agg.copy()
        agg_plot["label"] = title
        _plot_aggregate(graphs_dir / f"{stem}.png", title, agg_plot, ylabel)

        # Per-node breakdown
        _plot_per_node(
            graphs_dir / f"{stem}-per-node.png",
            f"{title} — per Node",
            per,
            ylabel,
            agg_df=agg,
        )


# ---------------------------------------------------------------------------
# Network graphs
# ---------------------------------------------------------------------------


def _render_network(graphs_dir: Path, network_data: dict, role_map: dict[str, str] | None = None):
    raw_df = _series_to_df(network_data.get("series", {}))
    if raw_df.empty:
        return

    # Convert all bytes to human-readable
    converted = raw_df["value"].apply(lambda v: pd.Series(_human_rate_bytes(v)))
    raw_df = raw_df.copy()
    raw_df["value"] = converted[0]
    raw_df["unit"] = converted[1]
    dominant_unit = raw_df["unit"].mode().iloc[0]

    # Aggregate overview: pod + node combined
    agg_keys = ["pod_rx_bps", "pod_tx_bps", "node_rx_bps", "node_tx_bps"]
    agg_df = raw_df[raw_df["metric_raw"].isin(agg_keys)].copy()
    agg_df["label"] = agg_df["metric_raw"].map(_METRIC_LABELS)
    _plot_aggregate(graphs_dir / "network-throughput.png", "Network Throughput", agg_df, dominant_unit)

    # Packet drops
    drop_df = raw_df[raw_df["metric_raw"] == "pod_drop_pps"].copy()
    drop_df["label"] = "Dropped Packets/s"
    _plot_aggregate(graphs_dir / "network-drops.png", "Network Packet Drops", drop_df, "Packets / second")

    # Per-node RX and TX breakdowns
    for base, title, stem in [
        ("node_rx_bps", "Node RX — per Node", "network-rx-per-node"),
        ("node_tx_bps", "Node TX — per Node", "network-tx-per-node"),
    ]:
        agg_base = raw_df[raw_df["metric_raw"] == base].copy()
        _, per = _split_per_node(raw_df, base, role_map=role_map)
        _plot_per_node(
            graphs_dir / f"{stem}.png",
            title,
            per,
            dominant_unit,
            agg_df=agg_base,
        )


# ---------------------------------------------------------------------------
# Token / request graphs
# ---------------------------------------------------------------------------


def _render_tokens(graphs_dir: Path, token_data: dict):
    raw_df = _series_to_df(token_data.get("series", {}))
    if raw_df.empty:
        return

    def _plot(path, title, keys, ylabel):
        sub = raw_df[raw_df["metric_raw"].isin(keys)].copy()
        sub["label"] = sub["metric_raw"].map(lambda k: _METRIC_LABELS.get(k, k))
        _plot_aggregate(path, title, sub, ylabel)

    _plot(graphs_dir / "request-queue.png",      "Queue Pressure",     ["ray_ongoing_requests", "ray_queue_len"],  "Requests")
    _plot(graphs_dir / "request-throughput.png", "Request Throughput", ["ray_http_rps", "ray_deployment_rps"],     "Requests / second")


# ---------------------------------------------------------------------------
# Benchmark graphs
# ---------------------------------------------------------------------------


def _render_benchmark(graphs_dir: Path, bench: dict):
    if not bench:
        return
    if bench.get("mode") == "task_suite":
        _render_benchmark_task_suite(graphs_dir, bench)
    else:
        _render_benchmark_repeated(graphs_dir, bench)


def _render_benchmark_task_suite(graphs_dir: Path, bench: dict):
    rows = []
    for item in bench.get("tasks", []):
        r = item.get("result", {})
        if r.get("skipped"):
            continue  # omit skipped tasks from charts (they have no timing data)
        rows.append({
            "Task": _task_label(item.get("name", "?")),
            "Round": item.get("round", 1),
            "TTFT (s)": r.get("ttft_seconds") or 0.0,
            "Generation time (s)": r.get("generation_time_seconds") or 0.0,
            "Total time (s)": r.get("total_time_seconds") or 0.0,
            "Prompt tokens": r.get("prompt_tokens") or r.get("effective_prompt_tokens") or 0,
            "Completion tokens": r.get("completion_tokens") or 0,
            "Gen tok/s": r.get("generation_tokens_per_second") or 0.0,
            "Total tok/s": r.get("total_tokens_per_second") or 0.0,
            "Per-GPU tok/s": r.get("estimated_per_gpu_output_tokens_per_second") or 0.0,
        })
    df = pd.DataFrame(rows)
    order = sorted(df["Task"].unique())
    w = max(8, len(order) * 1.4)

    # TTFT boxplot + jitter
    fig, ax = plt.subplots(figsize=(w, 5))
    sns.boxplot(data=df, x="Task", y="TTFT (s)", order=order, color="#fbbf24", width=0.5, ax=ax)
    sns.stripplot(data=df, x="Task", y="TTFT (s)", order=order, color="#1f2937", alpha=0.65, size=6, jitter=True, ax=ax)
    ax.set_title("Time to First Token (TTFT) by Task", pad=14)
    ax.set_ylabel("TTFT (seconds)", labelpad=8)
    ax.set_xlabel("")
    ax.tick_params(axis="x", rotation=35)
    _save(fig, graphs_dir / "benchmark-ttft.png")

    # Throughput grouped bar
    fig, ax = plt.subplots(figsize=(w, 5))
    tdf = df.melt(id_vars=["Task", "Round"], value_vars=["Gen tok/s", "Total tok/s"], var_name="Metric", value_name="Value")
    sns.barplot(data=tdf, x="Task", y="Value", hue="Metric", order=order, ax=ax)
    _add_bar_labels(ax, "%.0f")
    ax.set_title("Throughput by Task", pad=14)
    ax.set_ylabel("Tokens / second", labelpad=8)
    ax.set_xlabel("")
    ax.tick_params(axis="x", rotation=35)
    _place_legend(ax)
    _save(fig, graphs_dir / "benchmark-throughput.png")

    # TTFT per task/round (individual bars, labelled)
    df["Label"] = df.apply(lambda r: f"{r['Task']}\n(r{r['Round']})", axis=1)
    fig, ax = plt.subplots(figsize=(max(8, len(df) * 0.9), 5))
    sns.barplot(data=df, x="Label", y="TTFT (s)", color="#f59e0b", ax=ax)
    _add_bar_labels(ax, "%.2f")
    ax.set_title("TTFT per Task / Round", pad=14)
    ax.set_xlabel("")
    ax.set_ylabel("Seconds", labelpad=8)
    ax.tick_params(axis="x", rotation=45)
    _save(fig, graphs_dir / "benchmark-ttft-by-round.png")

    # ----- NEW: Latency breakdown — stacked TTFT + generation time -----
    # Use per-round rows so every bar is one (task, round) combination
    df_stack = df.copy()
    df_stack = df_stack[df_stack["Generation time (s)"] > 0]
    if not df_stack.empty:
        df_stack = df_stack.sort_values(["Task", "Round"])
        labels_stack = [f"{r['Task']}\n(r{int(r['Round'])})" for _, r in df_stack.iterrows()]
        fig, ax = plt.subplots(figsize=(max(10, len(df_stack) * 0.9), 5))
        ax.bar(labels_stack, df_stack["TTFT (s)"].values, label="TTFT (prefill)", color="#fbbf24")
        ax.bar(labels_stack, df_stack["Generation time (s)"].values,
               bottom=df_stack["TTFT (s)"].values, label="Generation", color="#60a5fa")
        ax.set_title("Latency Breakdown: Prefill vs Generation", pad=14)
        ax.set_ylabel("Seconds", labelpad=8)
        ax.set_xlabel("")
        ax.tick_params(axis="x", rotation=45)
        _place_legend(ax)
        _save(fig, graphs_dir / "benchmark-latency-breakdown.png")

    # ----- NEW: Round-over-round consistency (mean ± range per task) -----
    agg_rounds = (
        df.groupby("Task")
        .agg(
            ttft_mean=("TTFT (s)", "mean"),
            ttft_min=("TTFT (s)", "min"),
            ttft_max=("TTFT (s)", "max"),
            gen_mean=("Gen tok/s", "mean"),
            gen_min=("Gen tok/s", "min"),
            gen_max=("Gen tok/s", "max"),
        )
        .loc[order]
        .reset_index()
    )
    fig, axes = plt.subplots(1, 2, figsize=(max(12, len(order) * 2), 5))
    for ax_i, (col_mean, col_min, col_max, title, ylabel, color) in enumerate([
        ("ttft_mean", "ttft_min", "ttft_max", "TTFT Consistency Across Rounds", "Seconds", "#f59e0b"),
        ("gen_mean",  "gen_min",  "gen_max",  "Gen Throughput Consistency",      "Tokens / second", "#34d399"),
    ]):
        ax = axes[ax_i]
        yerr_lo = agg_rounds[col_mean] - agg_rounds[col_min]
        yerr_hi = agg_rounds[col_max] - agg_rounds[col_mean]
        ax.bar(agg_rounds["Task"], agg_rounds[col_mean], color=color, alpha=0.85, zorder=2)
        ax.errorbar(
            agg_rounds["Task"], agg_rounds[col_mean],
            yerr=[yerr_lo, yerr_hi],
            fmt="none", color="#1f2937", capsize=5, linewidth=1.8, zorder=3,
        )
        ax.set_title(title, pad=12)
        ax.set_ylabel(ylabel, labelpad=8)
        ax.set_xlabel("")
        ax.tick_params(axis="x", rotation=35)
    fig.suptitle("Round-over-Round Stability (bars = mean, whiskers = min/max)", fontsize=13, y=1.02)
    fig.tight_layout()
    _save(fig, graphs_dir / "benchmark-round-stability.png")

    # ----- NEW: Prompt-length vs TTFT scatter -----
    scatter_df = df[df["Prompt tokens"] > 0].copy()
    if not scatter_df.empty:
        fig, ax = plt.subplots(figsize=(9, 5))
        palette = sns.color_palette("deep", len(order))
        task_color = {t: c for t, c in zip(order, palette)}
        for task, grp in scatter_df.groupby("Task"):
            ax.scatter(grp["Prompt tokens"], grp["TTFT (s)"],
                       label=task, color=task_color[task], s=80, alpha=0.85, zorder=3)
        ax.set_title("Prompt Length vs TTFT (Prefill Cost)", pad=14)
        ax.set_xlabel("Prompt Tokens", labelpad=8)
        ax.set_ylabel("TTFT (seconds)", labelpad=8)
        ax.set_xscale("log")
        _place_legend(ax, title="Task")
        _save(fig, graphs_dir / "benchmark-prompt-vs-ttft.png")


def _render_benchmark_repeated(graphs_dir: Path, bench: dict):
    runs = bench.get("runs", [])
    df = pd.DataFrame([
        {
            "Round": item.get("round"),
            "TTFT (s)": item.get("result", {}).get("ttft_seconds") or 0.0,
            "Gen tok/s": item.get("result", {}).get("generation_tokens_per_second") or 0.0,
            "Total tok/s": item.get("result", {}).get("total_tokens_per_second") or 0.0,
        }
        for item in runs
    ])
    melted = df.melt(id_vars=["Round"], var_name="Metric", value_name="Value")
    fig, ax = plt.subplots(figsize=(10, 5))
    sns.lineplot(data=melted, x="Round", y="Value", hue="Metric", marker="o", linewidth=2.8, markersize=8, ax=ax)
    ax.set_title("Repeated Prompt Benchmark", pad=14)
    ax.set_xlabel("Round", labelpad=8)
    ax.set_ylabel("Value", labelpad=8)
    _place_legend(ax)
    _save(fig, graphs_dir / "benchmark-repeated.png")


# ---------------------------------------------------------------------------
# Summary markdown
# ---------------------------------------------------------------------------


def _write_summary_md(summary_md: Path, token: dict, network: dict, gpu: dict):
    ts = token.get("summary", {})
    ns = network.get("summary", {})
    gs = gpu.get("summary", {})
    gm_v, gm_u = _human_bytes(float(gs.get("gpu_mem_mb", {}).get("max", 0.0) or 0.0) * 1024 * 1024)
    prx_v, prx_u = _human_rate_bytes(float(ns.get("pod_rx_bps", {}).get("max", 0.0) or 0.0))
    ptx_v, ptx_u = _human_rate_bytes(float(ns.get("pod_tx_bps", {}).get("max", 0.0) or 0.0))
    nrx_v, nrx_u = _human_rate_bytes(float(ns.get("node_rx_bps", {}).get("max", 0.0) or 0.0))
    ntx_v, ntx_u = _human_rate_bytes(float(ns.get("node_tx_bps", {}).get("max", 0.0) or 0.0))
    summary_md.parent.mkdir(parents=True, exist_ok=True)
    summary_md.write_text("\n".join([
        "# Benchmark Window Summary",
        "",
        "## Request pressure",
        f"- Ongoing requests avg: {ts.get('ray_ongoing_requests', {}).get('avg', 'n/a')}",
        f"- Queue length max: {ts.get('ray_queue_len', {}).get('max', 'n/a')}",
        f"- HTTP request rate max: {ts.get('ray_http_rps', {}).get('max', 'n/a')}",
        f"- Deployment request rate max: {ts.get('ray_deployment_rps', {}).get('max', 'n/a')}",
        "",
        "## GPU behaviour",
        f"- GPU util avg %: {gs.get('gpu_util_pct', {}).get('avg', 'n/a')}",
        f"- GPU memory max: {gm_v:.2f} {gm_u}",
        f"- GPU power avg W: {gs.get('gpu_power_w', {}).get('avg', 'n/a')}",
        f"- GPU temp max C: {gs.get('gpu_temp_c', {}).get('max', 'n/a')}",
        "",
        "## Network behaviour",
        f"- Pod RX max: {prx_v:.2f} {prx_u}",
        f"- Pod TX max: {ptx_v:.2f} {ptx_u}",
        f"- Node RX max: {nrx_v:.2f} {nrx_u}",
        f"- Node TX max: {ntx_v:.2f} {ntx_u}",
        "",
        "Graphs: metrics/graphs/",
    ]) + "\n")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    sns.set_theme(style="whitegrid", context="talk", palette="deep")
    plt.rcParams.update({
        "axes.titlesize": 15,
        "axes.titleweight": "bold",
        "axes.labelsize": 13,
        "lines.linewidth": 2.5,
        "legend.framealpha": 0.85,
        "legend.edgecolor": "none",
        "legend.fontsize": 11,
        "axes.facecolor": "#f9f9f9",
    })

    exp_dir = Path(os.environ.get("EXPERIMENT_DIR", ""))
    if not exp_dir:
        print("ERROR: EXPERIMENT_DIR env var not set.")
        return 1

    results_dir = Path(os.environ.get("EXPERIMENT_RESULTS_DIR", exp_dir / "results"))
    metrics_dir = Path(os.environ.get("EXPERIMENT_METRICS_DIR", exp_dir / "metrics"))
    graphs_dir = Path(os.environ.get("EXPERIMENT_GRAPHS_DIR", metrics_dir / "graphs"))
    graphs_dir.mkdir(parents=True, exist_ok=True)

    # Load node topology so per-node plots show Head / Worker roles
    role_map = _parse_topology(results_dir / "topology.txt")
    if role_map:
        roles_str = ", ".join(f"{v}: {k}" for k, v in sorted(role_map.items(), key=lambda x: x[1]))
        print(f"Node roles loaded: {roles_str}")
    else:
        print("No topology.txt found — node roles will show as plain IPs.")

    benchmark_file = next(iter(sorted(results_dir.glob("benchmark-*.json"))), None)
    if benchmark_file:
        bench = _load_json(benchmark_file) or {}
        _render_benchmark(graphs_dir, bench)

    token = _load_json(metrics_dir / "token-metrics.json") or {}
    _render_tokens(graphs_dir, token)

    network = _load_json(metrics_dir / "network-metrics.json") or {}
    _render_network(graphs_dir, network, role_map=role_map)

    gpu = _load_json(metrics_dir / "gpu-metrics.json") or {}
    _render_gpu(graphs_dir, gpu, role_map=role_map)

    _write_summary_md(metrics_dir / "prometheus" / "summary.md", token, network, gpu)

    print(f"Done - graphs written to {graphs_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
