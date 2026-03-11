#!/usr/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/lane.sh"

require_supported_lane

SKIP_VALIDATE="${SKIP_VALIDATE:-true}"
SKIP_STARTUP_LATENCY="${SKIP_STARTUP_LATENCY:-true}"

ensure_experiment_dir >/dev/null
record_experiment_metadata
record_scenario_metadata

if [[ "${SKIP_VALIDATE}" != "true" ]]; then
  run_step "Validate lane" "${ROOT_DIR}/scripts/eks/validate-lane.sh"
else
  echo "==> Skip validate lane (SKIP_VALIDATE=true)"
fi

if [[ "${SKIP_STARTUP_LATENCY}" != "true" ]]; then
  run_step "Capture startup latency" "${ROOT_DIR}/scripts/eks/capture-startup-latency.sh"
else
  echo "==> Skip startup latency capture (SKIP_STARTUP_LATENCY=true)"
fi

run_step "Benchmark lane" "${ROOT_DIR}/scripts/eks/benchmark-lane.sh"
run_step "Capture Prometheus metrics" "${ROOT_DIR}/scripts/eks/capture-prometheus-metrics.sh"
run_step "Capture topology" "${ROOT_DIR}/scripts/eks/report-lane-topology.sh"
run_step "Capture observed metrics" "${ROOT_DIR}/scripts/eks/capture-observed-metrics.sh"
run_step "Render experiment graphs" python3 "${ROOT_DIR}/scripts/eks/render-experiment-graphs.py"

echo "Experiment artifacts captured at: ${EXPERIMENT_DIR}"
