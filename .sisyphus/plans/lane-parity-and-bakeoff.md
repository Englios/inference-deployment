# Lane Parity & Bakeoff Readiness

## TL;DR

> **Quick Summary**: Fix all known correctness bugs across both the `ray-vllm` and `dynamo-vllm` inference lanes, plus shared pipeline bugs, so that a valid head-to-head bakeoff can be run. Scaffold Dynamo's advanced features (disaggregated prefill/decode, KV-aware routing, NIXL) with clear experimental gates — enabling future work without breaking current stability.
>
> **Deliverables**:
> - KubeRay lane: metrics scraping fully working (head + workers), autoscaling parameterized, version alignment
> - Dynamo lane: PP correctly passed to workers, metrics port-forward fixed, disagg template scaffolded, NIXL/KV-routing documented with flags commented-in but gated
> - Shared pipeline: `benchmark_vllm.py` metrics wired, `render-experiment-graphs.py` path bug fixed, `lane.sh` JSON hardened
> - Infra: missing tfvars, taint variable, Ansible multi-run + artifact threading
> - Both lanes ready to run `ansible-playbook experiment.yml -e lane=ray-vllm` and `...lane=dynamo-vllm` and produce comparable output
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 4 waves
> **Critical Path**: T1 (shared metrics fix) → T7 (Dynamo lane fixes) → T12 (pipeline bugs) → T18 (validation)

---

## Context

### Original Request
Evaluate Dynamo vs KubeRay for distributed LLM inference on EKS with frequent node shape changes. After deep research across 10 background agents, the decision was: keep both lanes, fix all known bugs, run a proper bakeoff.

### Interview Summary
- **Primary Goal**: Fix everything → run bakeoff → let data decide between KubeRay and Dynamo
- **Dynamo scope**: Aggregated mode fixes + scaffold disaggregated template + document KV-routing and NIXL integration points (with experimental gates, since KVBM+vLLM crashes upstream: #5857)
- **Tests**: No unit tests — running the actual EKS experiment IS the test. All QA is agent-executable (template renders, grep checks, curl/kubectl dry-runs where possible)
- **Lanes**: Both remain active in parallel. Neither is deprecated.

### Metis Review
**Identified Gaps** (addressed):
- Scaffold vs Enable split for KVBM/disagg (unsafe to enable, safe to scaffold) → each advanced feature task explicitly gates "scaffold only" vs "enable when stable"
- Validation tiers tagged per task: tier-0 (agent-verifiable), tier-1 (needs kubeconfig dry-run), tier-2 (needs live EKS)
- NIXL flags = `--kv-transfer-config` JSON arg passed to `python3 -m dynamo.vllm` worker — not a separate component; referenced in Dynamo vLLM backend docs
- Ray head metrics port 8080 IS the Ray agent metrics endpoint (part of Ray's built-in agent, just undeclared as containerPort) — fix = add explicit containerPort declaration
- Bug dependency: bug #19 (EXPERIMENT_DIR threading) must be fixed together with #18 (multi-run) to avoid partial state

---

## Work Objectives

### Core Objective
Bring both inference lanes to a state where a fair, reproducible, metrics-producing bakeoff can be run against the same model, same prompt suite, and same concurrency sweep — then document what to compare.

### Concrete Deliverables
- `.eks/ray/ray-vllm-service.yaml.tpl` — containerPort 8080 declared; worker ServiceMonitor added; autoscaling vars parameterized
- `.eks/monitoring/ray-worker-servicemonitor.yaml` — new file, scrapes Ray worker pods
- `.eks/dynamo/vllm/agg.yaml.tpl` — `--pipeline-parallel-size` added to worker args
- `.eks/dynamo/vllm/disagg.yaml.tpl` — new file, disaggregated P/D template (scaffolded, gated)
- `scripts/eks/benchmark-dynamo-vllm.sh` — metrics port-forward fixed (9090 not 8000)
- `scripts/eks/validate-dynamo-vllm.sh` — metrics port-forward added
- `scripts/eks/benchmark_vllm.py` — `metrics_url` wired; KV cache + queue pressure metrics populated
- `scripts/eks/render-experiment-graphs.py` — EXPERIMENT_DIR detection fixed
- `scripts/eks/lane.sh` — JSON generation hardened
- `scripts/eks/*.sh` — `python3.11` → `python3` across all scripts
- `terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` — new file
- `terraform/stacks/eks-inference/variables.tf` — `node_group_taints` variable added
- `ansible/playbooks/destroy.sh` — `-auto-approve` added
- `ansible/playbooks/orchestrate_experiment.yml` — multi-run loop added
- `ansible/playbooks/lane_benchmark.yml`, `lane_validate.yml` — EXPERIMENT_DIR threaded
- `ansible/playbooks/cleanup_namespace.yml` — secret deletion scoped to lane secrets only

### Definition of Done
- [ ] `scripts/eks/inference_config.py --lane dynamo-vllm` renders `agg.yaml.tpl` containing `--pipeline-parallel-size 2` in worker args
- [ ] `grep 'containerPort: 8080' .eks/ray/ray-vllm-service.yaml.tpl` returns a match
- [ ] `grep 'targetPort: 8080' .eks/monitoring/ray-metrics-service.yaml` returns a match
- [ ] `grep 'metrics_url' scripts/eks/benchmark_vllm.py | grep -v '#'` shows active (non-commented) use
- [ ] `python3 scripts/eks/render-experiment-graphs.py --help` does not silently use cwd
- [ ] `ls terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` exits 0
- [ ] `grep 'node_group_taints' terraform/stacks/eks-inference/variables.tf` returns a match
- [ ] `grep '\-\-auto-approve' ansible/playbooks/destroy.sh` (or equivalent) returns a match
- [ ] `cat .eks/dynamo/vllm/disagg.yaml.tpl` exists with Prefill + Decode component stubs

### Must Have
- Both lanes produce a `benchmark-{lane}.json` in `EXPERIMENT_DIR/results/` with TTFT, tokens/sec, KV cache usage, queue pressure
- Dynamo lane passes `--pipeline-parallel-size` to the worker
- Ray lane scrapes both head and worker pods in Prometheus
- Disagg template exists and renders cleanly (even if not deployable due to upstream crash)
- All file references in this plan exist in the repo (verified before writing tasks)

### Must NOT Have (Guardrails)
- **NO enabling KVBM** until upstream crash bug `ai-dynamo/dynamo#5857` is closed — scaffold only, flags commented out with `# UNSTABLE: enable when #5857 is fixed`
- **NO activating Dynamo KV-aware router** in manifests — document the integration point only, don't wire it in agg.yaml.tpl yet
- **NO rewriting scripts** in different languages — fix fragility, don't rewrite
- **NO new unit test files** — user explicitly said no
- **NO modifying existing `.tfvars` files** — only add new ones
- **NO changing model, benchmark prompts, or concurrency defaults** — those are experiment variables
- **NO scope-creep into Grafana dashboard changes** — Prometheus scrape config only
- **NO fixing upstream Dynamo bugs** (KVBM crash, multi-node TP×PP limit) — link, document, move on

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: NO
- **Automated tests**: None (user explicit)
- **Framework**: N/A

### QA Policy

**Validation tiers** (tagged per task):
- **Tier 0** — Agent-executable, no cluster needed: template rendering, grep/static checks, file existence
- **Tier 1** — Needs kubeconfig dry-run: `kubectl apply --dry-run=client`, `terraform validate`
- **Tier 2** — Needs live EKS: actual port-forward validation, Prometheus scrape verification

Every task has at least one Tier-0 scenario. Tier-2 tasks are marked with `[TIER-2: requires live EKS]`.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — independent fixes, all parallel):
├── Task 1: Ray metrics — containerPort 8080 + worker ServiceMonitor    [quick]
├── Task 2: Ray autoscaling — parameterize min/max replicas             [quick]
├── Task 3: Ray version alignment                                        [quick]
├── Task 4: Dynamo PP bug — add --pipeline-parallel-size to agg.yaml.tpl [quick]
├── Task 5: Dynamo metrics port-forward fix (benchmark + validate scripts) [quick]
├── Task 6: Infra fixes (g7e-1x2 tfvars + node_group_taints variable)  [quick]
└── Task 7: Ansible infra fixes (destroy.sh auto-approve, cleanup scope) [quick]

Wave 2 (After Wave 1 — depend on at least one Wave 1 fix):
├── Task 8: benchmark_vllm.py — wire metrics_url + populate KV/queue metrics [unspecified-high]
├── Task 9: render-experiment-graphs.py — EXPERIMENT_DIR path fix       [quick]
├── Task 10: lane.sh — JSON generation hardening                        [unspecified-high]
├── Task 11: python3.11 → python3 sweep across all scripts              [quick]
└── Task 12: Dynamo disagg.yaml.tpl — scaffold Prefill+Decode template  [unspecified-high]

Wave 3 (After Wave 2 — integration-level):
├── Task 13: Ansible multi-run + EXPERIMENT_DIR threading               [unspecified-high]
└── Task 14: NIXL + KV-routing documentation (comments in agg.yaml.tpl) [quick]

Wave 4 (After Wave 3 — final verification):
├── Task 15: Render both lane templates and verify args                  [quick]
├── Task 16: Grep-audit all guardrails (no KVBM enabled, no bad ports)  [quick]
├── Task 17: Bakeoff readiness checklist                                [unspecified-high]
└── Task 18: Final review + commit                                       [quick]

Critical Path: T4 → T12 (disagg depends on agg being correct first)
              T8 → T17 (metrics wired needed for bakeoff readiness check)
Parallel Speedup: ~65% faster than sequential
Max Concurrent: 7 (Wave 1)
```

### Agent Dispatch Summary

- **Wave 1**: 7 tasks — all `quick`
- **Wave 2**: 5 tasks — T8 `unspecified-high`, T9 `quick`, T10 `unspecified-high`, T11 `quick`, T12 `unspecified-high`
- **Wave 3**: 2 tasks — T13 `unspecified-high`, T14 `quick`
- **Wave 4**: 4 tasks — T15 `quick`, T16 `quick`, T17 `unspecified-high`, T18 `quick`

---

## TODOs

<!-- WAVE 1 -->

- [ ] 1. Ray metrics — declare containerPort 8080 on head + add worker ServiceMonitor

  **What to do**:
  - In `.eks/ray/ray-vllm-service.yaml.tpl`, add `- containerPort: 8080\n  name: metrics` to the `headGroupSpec.template.spec.containers[0].ports` list (after the existing `dashboard` port on line 69)
  - Create `.eks/monitoring/ray-worker-servicemonitor.yaml` — a `ServiceMonitor` that selects pods by label `ray.io/node-type: worker` in namespace `inference-engine`, scraping port `metrics` (8080) at `/metrics` every 30s from the `monitoring` namespace
  - Verify `ray-metrics-service.yaml` already targets `targetPort: 8080` (it does — no change needed there)

  **Must NOT do**:
  - Do NOT change the `ray-metrics-service.yaml` selector or ports — they are already correct
  - Do NOT add Grafana dashboard changes

  **Recommended Agent Profile**:
  > Quick YAML edits to two files — no logic, no code.
  - **Category**: `quick`
    - Reason: Pure YAML line insertions, no research needed
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4, 5, 6, 7)
  - **Blocks**: None
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `.eks/ray/ray-vllm-service.yaml.tpl:64-72` — existing `ports` block on head container; add `metrics` port after `dashboard`
  - `.eks/monitoring/ray-metrics-servicemonitor.yaml:1-19` — existing head ServiceMonitor; use identical structure for the new worker one, change selector label to `ray.io/node-type: worker` and name to `ray-worker-metrics`
  - `.eks/monitoring/vllm-head-servicemonitor.yaml` — cross-reference for ServiceMonitor shape in this repo

  **Acceptance Criteria**:
  - [ ] `grep 'containerPort: 8080' .eks/ray/ray-vllm-service.yaml.tpl` exits 0
  - [ ] `grep 'name: metrics' .eks/ray/ray-vllm-service.yaml.tpl` exits 0 (for the new port entry)
  - [ ] File `.eks/monitoring/ray-worker-servicemonitor.yaml` exists
  - [ ] `grep 'ray.io/node-type: worker' .eks/monitoring/ray-worker-servicemonitor.yaml` exits 0

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: containerPort 8080 declared on Ray head
    Tool: Bash
    Preconditions: file .eks/ray/ray-vllm-service.yaml.tpl exists
    Steps:
      1. Run: grep -A2 'name: metrics' .eks/ray/ray-vllm-service.yaml.tpl
      2. Assert output contains 'containerPort: 8080'
    Expected Result: line 'containerPort: 8080' appears under 'name: metrics' in the ports block
    Failure Indicators: grep returns 0 matches or 'name: metrics' only appears in the vllm-head service
    Evidence: .sisyphus/evidence/task-1-ray-head-metrics-port.txt

  Scenario: Worker ServiceMonitor file exists and selects workers
    Tool: Bash
    Preconditions: task-1 implementation complete
    Steps:
      1. Run: cat .eks/monitoring/ray-worker-servicemonitor.yaml
      2. Assert file contains 'ray.io/node-type: worker'
      3. Assert file contains 'port: metrics'
    Expected Result: valid ServiceMonitor YAML targeting worker pods
    Failure Indicators: file missing or selector targets head pods
    Evidence: .sisyphus/evidence/task-1-ray-worker-servicemonitor.txt
  ```

  **Commit**: YES (group Wave-1-ray)
  - Message: `fix(ray): declare metrics containerPort 8080 on head, add worker ServiceMonitor`
  - Files: `.eks/ray/ray-vllm-service.yaml.tpl`, `.eks/monitoring/ray-worker-servicemonitor.yaml`

---

- [ ] 2. Ray autoscaling — parameterize min_replicas and max_replicas

  **What to do**:
  - In `.eks/ray/ray-vllm-service.yaml.tpl` lines 25-26, replace hardcoded `min_replicas: 1` and `max_replicas: 1` with `min_replicas: ${ray_serve_min_replicas}` and `max_replicas: ${ray_serve_max_replicas}`
  - In `.eks/inference-profile.json`, confirm or add `ray.serve_min_replicas` and `ray.serve_max_replicas` fields (default: 1 and 4 respectively)
  - In `scripts/eks/inference_config.py`, ensure the two new keys are mapped to template vars `ray_serve_min_replicas` and `ray_serve_max_replicas`

  **Must NOT do**:
  - Do NOT change `target_ongoing_requests`, `max_ongoing_requests`, or health-check intervals — those are experiment variables
  - Do NOT alter `workerGroupSpecs.minReplicas` / `maxReplicas` (those are Ray cluster node replicas, already parameterized on lines 85-86)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Two-line template change + JSON profile field additions + one config.py mapping
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4, 5, 6, 7)
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `.eks/ray/ray-vllm-service.yaml.tpl:23-32` — `autoscaling_config` block; lines 25-26 are the hardcoded values to parameterize
  - `.eks/ray/ray-vllm-service.yaml.tpl:84-88` — `workerGroupSpecs` already uses `${ray_worker_min_replicas}` / `${ray_worker_max_replicas}` — use the same pattern for serve replicas
  - `.eks/inference-profile.json` — add keys under `ray` object, matching existing style like `ray.head.gpus`

  **Acceptance Criteria**:
  - [ ] `grep 'ray_serve_min_replicas' .eks/ray/ray-vllm-service.yaml.tpl` exits 0
  - [ ] `grep 'ray_serve_max_replicas' .eks/ray/ray-vllm-service.yaml.tpl` exits 0
  - [ ] `grep 'serve_min_replicas' .eks/inference-profile.json` exits 0

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: Template uses variable substitution for autoscaling
    Tool: Bash
    Preconditions: file .eks/ray/ray-vllm-service.yaml.tpl exists
    Steps:
      1. Run: grep 'min_replicas:\|max_replicas:' .eks/ray/ray-vllm-service.yaml.tpl
      2. Assert NO line reads 'min_replicas: 1' literally (only template vars allowed)
      3. Assert lines contain '${ray_serve_min_replicas}' and '${ray_serve_max_replicas}'
    Expected Result: both lines use ${...} substitution, not hardcoded integers
    Failure Indicators: any literal 'min_replicas: 1' or 'max_replicas: 1' remaining
    Evidence: .sisyphus/evidence/task-2-ray-autoscaling-params.txt
  ```

  **Commit**: YES (group Wave-1-ray)
  - Message: `fix(ray): parameterize serve autoscaling min/max replicas via profile`
  - Files: `.eks/ray/ray-vllm-service.yaml.tpl`, `.eks/inference-profile.json`, `scripts/eks/inference_config.py`

---

- [ ] 3. Ray version alignment

  **What to do**:
  - In `.eks/inference-profile.json`, find the `ray.ray_version` field (currently `2.52.0`) and update it to `2.54.0` to match the actual image `anyscale/ray-llm:2.54.0-py311-cu128`
  - Verify `scripts/eks/inference_config.py` maps `ray.ray_version` → `ray_version` template var (already exists; confirm, don't change if correct)
  - No template change needed — `.eks/ray/ray-vllm-service.yaml.tpl:39` already uses `${ray_version}`

  **Must NOT do**:
  - Do NOT change the image tag itself — only align the `ray_version` field to match the existing image
  - Do NOT bump any other version fields

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single JSON field update
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `.eks/inference-profile.json` — find `ray.ray_version` and update to `2.54.0`
  - `.eks/ray/ray-vllm-service.yaml.tpl:39` — `rayVersion: "${ray_version}"` — confirm this var is used

  **Acceptance Criteria**:
  - [ ] `grep '2.54.0' .eks/inference-profile.json` exits 0
  - [ ] `grep '2.52.0' .eks/inference-profile.json` returns 0 matches (old value removed)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: ray_version in profile matches image tag
    Tool: Bash
    Preconditions: .eks/inference-profile.json exists
    Steps:
      1. Run: python3 -c "import json; p=json.load(open('.eks/inference-profile.json')); print(p['ray']['ray_version'])"
      2. Assert printed value is '2.54.0'
    Expected Result: output is '2.54.0'
    Failure Indicators: output is '2.52.0' or any other version
    Evidence: .sisyphus/evidence/task-3-ray-version.txt
  ```

  **Commit**: YES (group Wave-1-ray)
  - Message: `fix(ray): align ray_version in profile to match 2.54.0 image`
  - Files: `.eks/inference-profile.json`

---

- [ ] 4. Dynamo PP bug — add --pipeline-parallel-size to agg.yaml.tpl worker args

  **What to do**:
  - In `.eks/dynamo/vllm/agg.yaml.tpl`, in the `VllmWorker` command args block (lines 91-100), add `--pipeline-parallel-size ${pipeline_parallel_size}` as a new arg after `--tensor-parallel-size ${tensor_parallel_size}` (line 95)
  - The var `pipeline_parallel_size` is already available in the template render path (confirmed: `inference-profile.json` has `engine.pipeline_parallel_size: 2`)

  **Must NOT do**:
  - Do NOT add NIXL, KVBM, or KV-routing flags in this task — those belong in Task 14
  - Do NOT change the Frontend component — only the VllmWorker command args

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single line insertion in a YAML template
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 5, 6, 7)
  - **Blocks**: Task 12 (disagg template should also include this arg; easier after agg is correct)
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `.eks/dynamo/vllm/agg.yaml.tpl:91-100` — the worker command args block; insert after `--tensor-parallel-size ${tensor_parallel_size}` on line 95
  - `.eks/ray/ray-vllm-service.yaml.tpl:19-21` — Ray template already passes both TP and PP — use as correctness reference for expected arg shape

  **Acceptance Criteria**:
  - [ ] `grep 'pipeline-parallel-size' .eks/dynamo/vllm/agg.yaml.tpl` exits 0
  - [ ] `python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane dynamo-vllm --output-root .eks/rendered` succeeds
  - [ ] `grep 'pipeline-parallel-size' .eks/rendered/dynamo/vllm/agg.yaml` exits 0 (rendered output contains the arg)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: Rendered Dynamo agg.yaml contains PP arg
    Tool: Bash
    Preconditions: inference_config.py render succeeds
    Steps:
      1. Run: python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane dynamo-vllm --output-root .eks/rendered
      2. Run: grep 'pipeline-parallel-size' .eks/rendered/dynamo/vllm/agg.yaml
      3. Assert output contains '--pipeline-parallel-size 2'
    Expected Result: '--pipeline-parallel-size 2' present in rendered worker command args
    Failure Indicators: grep returns 0 matches; PP silently dropped
    Evidence: .sisyphus/evidence/task-4-dynamo-pp-arg.txt
  ```

  **Commit**: YES (group Wave-1-dynamo)
  - Message: `fix(dynamo): pass --pipeline-parallel-size to vllm worker in agg template`
  - Files: `.eks/dynamo/vllm/agg.yaml.tpl`

---

- [ ] 5. Dynamo metrics port-forward fix (benchmark + validate scripts)

  **What to do**:
  - In `scripts/eks/benchmark-dynamo-vllm.sh` line 28: the port-forward command maps `"${METRICS_PORT}:8000"` — change `:8000` to `:${metrics_port_remote}` where `metrics_port_remote` reads from the inference profile, OR simply replace the hardcoded `8000` with the env var `"${METRICS_PORT}:$(config_value runtime.metrics_port)"`. The Dynamo metrics port is 9090 per `inference-profile.json`
  - In `scripts/eks/validate-dynamo-vllm.sh` line 13: the port-forward only forwards the HTTP port; add a second forward for the metrics port: `"${METRICS_PORT:-18001}:$(config_value runtime.metrics_port)"` appended to the same `kubectl port-forward` command. Add `METRICS_PORT="${METRICS_PORT:-18001}"` near line 9
  - Do NOT change any other logic in either script

  **Must NOT do**:
  - Do NOT change `LOCAL_PORT` or the primary HTTP forward — only fix the metrics port mapping
  - Do NOT add any validation of metrics content — just ensure port-forward is wired correctly

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: One-line fix in two bash scripts
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `scripts/eks/benchmark-dynamo-vllm.sh:28` — line with the buggy `:8000` remote port; `METRICS_PORT` local var is already set on line 10
  - `scripts/eks/validate-dynamo-vllm.sh:13` — port-forward that needs the second mapping added
  - `scripts/eks/benchmark-ray-vllm.sh` — reference for how the Ray benchmark wires its metrics port-forward (correct pattern)
  - `.eks/inference-profile.json` — `runtime.metrics_port: 9090` is the correct remote port

  **Acceptance Criteria**:
  - [ ] `grep '8000' scripts/eks/benchmark-dynamo-vllm.sh` returns 0 matches (hardcoded 8000 removed)
  - [ ] `grep 'METRICS_PORT' scripts/eks/validate-dynamo-vllm.sh` returns a match (port var added)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: benchmark-dynamo-vllm.sh no longer hardcodes port 8000
    Tool: Bash
    Steps:
      1. Run: grep ':8000' scripts/eks/benchmark-dynamo-vllm.sh
      2. Assert output is empty (exit code 1 from grep is acceptable, meaning no match)
    Expected Result: no literal ':8000' remaining in the benchmark script
    Failure Indicators: grep returns any match
    Evidence: .sisyphus/evidence/task-5-dynamo-metrics-port.txt

  Scenario: validate-dynamo-vllm.sh includes metrics port-forward
    Tool: Bash
    Steps:
      1. Run: grep 'METRICS_PORT\|18001\|metrics_port' scripts/eks/validate-dynamo-vllm.sh
      2. Assert at least one match is returned
    Expected Result: metrics port variable and/or value present in validate script
    Failure Indicators: grep returns 0 matches
    Evidence: .sisyphus/evidence/task-5-dynamo-validate-metrics.txt
  ```

  **Commit**: YES (group Wave-1-dynamo)
  - Message: `fix(dynamo): fix metrics port-forward in benchmark (9090 not 8000) and add to validate`
  - Files: `scripts/eks/benchmark-dynamo-vllm.sh`, `scripts/eks/validate-dynamo-vllm.sh`

---

- [ ] 6. Infra fixes — add g7e-1x2 tfvars + node_group_taints variable

  **What to do**:
  - Create `terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` with 1 inference node of `g7e.12xlarge` (single-node baseline experiment shape). Copy structure from `terraform.g7e-2x2.tfvars`, set `node_group_size = 1`
  - In `terraform/stacks/eks-inference/variables.tf`, append a new variable `node_group_taints` of type `list(object({ key=string, value=string, effect=string }))` with `default = []`

  **Must NOT do**:
  - Do NOT edit `terraform.g7e-2x2.tfvars` or `terraform.g7e-1x4.tfvars` or `terraform.tfvars` — add a new file only
  - Do NOT wire the taint variable into `main.tf` unless the module already accepts it — just declare the variable (the executor should check `main.tf` first)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: New tfvars file (copy/edit) + appending one variable block to variables.tf
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `terraform/stacks/eks-inference/terraform.g7e-2x2.tfvars:1-16` — canonical shape to copy for new 1x2 file
  - `terraform/stacks/eks-inference/variables.tf:121-127` — `node_group_labels` variable block; use same `map` → `list(object)` style for taints
  - `terraform/stacks/eks-inference/terraform.g7e-1x4.tfvars` — cross-check naming convention (g7e-NxM = N nodes × M GPUs per node; g7e.12xlarge has 2 GPUs, so 1x2 = 1 node × 2 GPUs)

  **Acceptance Criteria**:
  - [ ] `ls terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` exits 0
  - [ ] `grep 'node_group_size.*1' terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars` exits 0
  - [ ] `grep 'node_group_taints' terraform/stacks/eks-inference/variables.tf` exits 0

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: New tfvars file has correct node count
    Tool: Bash
    Steps:
      1. Run: python3 -c "import re; c=open('terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars').read(); m=re.search(r'node_group_size\s*=\s*(\d+)', c); print(m.group(1))"
      2. Assert printed value is '1'
    Expected Result: node_group_size is 1
    Failure Indicators: value is 2 or file not found
    Evidence: .sisyphus/evidence/task-6-tfvars-1x2.txt

  Scenario: node_group_taints variable declared in variables.tf
    Tool: Bash
    Steps:
      1. Run: grep -A5 'node_group_taints' terraform/stacks/eks-inference/variables.tf
      2. Assert output shows a variable block with type containing 'list'
    Expected Result: variable 'node_group_taints' with list type and empty default
    Failure Indicators: grep returns 0 matches
    Evidence: .sisyphus/evidence/task-6-taint-variable.txt
  ```

  **Commit**: YES (group Wave-1-infra)
  - Message: `fix(infra): add g7e-1x2 tfvars for single-node baseline, declare node_group_taints variable`
  - Files: `terraform/stacks/eks-inference/terraform.g7e-1x2.tfvars`, `terraform/stacks/eks-inference/variables.tf`

---

- [ ] 7. Ansible infra fixes — destroy.sh auto-approve + cleanup_namespace.yml secret scope

  **What to do**:
  - In `scripts/eks/destroy.sh` line 19: append `-auto-approve` to the `terraform destroy` command so it reads: `"${TF_BIN}" -chdir="terraform/stacks/eks-inference" destroy -var-file="${tfvars_relative}" -auto-approve`
  - In `ansible/playbooks/cleanup_namespace.yml` lines 24-29: the "Delete non-default secrets" task uses `grep -v 'default-token'` which deletes ALL non-default secrets including secrets from other lanes. Scope it to only delete secrets whose names match the lane pattern. Replace the shell command with: `kubectl -n inference-engine get secret -o name | grep -E '(ray-vllm|dynamo-vllm|hf-token|vllm)' | xargs -r kubectl -n inference-engine delete` — this targets only lane-managed secrets

  **Must NOT do**:
  - Do NOT add `--force` or `--cascade` flags to destroy
  - Do NOT change any other cleanup targets (all, pvc) in cleanup_namespace.yml

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: One flag added to a shell command, one grep pattern changed in YAML
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `scripts/eks/destroy.sh:19` — the `terraform destroy` call; append `-auto-approve`
  - `ansible/playbooks/cleanup_namespace.yml:24-29` — the secret deletion task with the too-broad grep
  - `scripts/eks/deploy-ray-vllm.sh` — to identify what secret names the Ray lane creates (confirms `ray-vllm-secrets` is the pattern)
  - `scripts/eks/deploy-dynamo-vllm.sh` — to identify what secret names Dynamo creates (confirms `hf-token-secret`)

  **Acceptance Criteria**:
  - [ ] `grep 'auto-approve' scripts/eks/destroy.sh` exits 0
  - [ ] `grep 'ray-vllm\|dynamo-vllm\|hf-token' ansible/playbooks/cleanup_namespace.yml` exits 0 (new scoped grep pattern present)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: destroy.sh contains -auto-approve
    Tool: Bash
    Steps:
      1. Run: grep 'auto-approve' scripts/eks/destroy.sh
      2. Assert output contains 'auto-approve' on the terraform destroy line
    Expected Result: '-auto-approve' flag present in destroy command
    Failure Indicators: grep returns 0 matches
    Evidence: .sisyphus/evidence/task-7-destroy-autoapprove.txt

  Scenario: cleanup_namespace.yml only deletes lane-scoped secrets
    Tool: Bash
    Steps:
      1. Run: grep -A3 'non-default secrets' ansible/playbooks/cleanup_namespace.yml
      2. Assert output does NOT contain 'grep -v default-token' (old broad pattern gone)
      3. Assert output contains a lane-specific grep pattern (e.g., 'ray-vllm\|dynamo-vllm')
    Expected Result: secret deletion scoped to lane-pattern secrets only
    Failure Indicators: 'grep -v default-token' pattern still present
    Evidence: .sisyphus/evidence/task-7-cleanup-secret-scope.txt
  ```

  **Commit**: YES (group Wave-1-infra)
  - Message: `fix(ansible): add -auto-approve to destroy.sh, scope secret cleanup to lane secrets`
  - Files: `scripts/eks/destroy.sh`, `ansible/playbooks/cleanup_namespace.yml`

---

<!-- WAVE 2 -->

- [ ] 8. benchmark_vllm.py — wire metrics_url + populate KV cache and queue pressure metrics

  **What to do**:
  - In `scripts/eks/benchmark_vllm.py`, the `benchmark()` function (line 190) accepts `metrics_url` but never uses it. After the HTTP completion loop (around line 290), add a call to a new helper `_fetch_prometheus_metrics(metrics_url)` that:
    - HTTP GETs `{metrics_url}` (plain text Prometheus exposition format)
    - Parses lines matching `vllm:gpu_cache_usage_perc` (or `vllm:cache_config_info` / `vllm:gpu_prefix_cache_hit_rate`), `vllm:cpu_cache_usage_perc`, `vllm:num_requests_running`, `vllm:num_requests_waiting`
    - Returns a dict with keys matching the `kv_cache_metrics` and `queue_pressure_metrics` structures (each with `latest`, `max`, `avg` — since this is a point-in-time scrape, set all three to the scraped value)
    - On any exception (connection refused, timeout), returns empty metric summaries (graceful fallback — never crash the benchmark)
  - Replace the `kv_cache_metrics` and `queue_pressure_metrics` placeholder dicts (lines 291-300) with the values returned from `_fetch_prometheus_metrics(metrics_url)`
  - The `metrics_url` is already passed through correctly from `main()` (line 601) through `run_task_suite()` and `run_repeated_prompt_benchmark()` down to `benchmark()` — no call-site changes needed

  **Must NOT do**:
  - Do NOT add any new pip dependencies — use only `urllib.request` (already imported) for HTTP
  - Do NOT change the output JSON schema — only populate currently-null fields
  - Do NOT crash on metrics fetch failure — always fall back to `empty_metric_summary()`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Requires understanding Prometheus text exposition format, vLLM metric names, and the existing benchmark output schema
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 9, 10, 11, 12)
  - **Blocks**: Task 17 (bakeoff readiness check validates metrics are populated)
  - **Blocked By**: None (Wave 1 tasks touch different files)

  **References**:

  **Pattern References**:
  - `scripts/eks/benchmark_vllm.py:58-64` — `http_json()` helper; write `_fetch_prometheus_metrics()` alongside it using `urllib.request` similarly
  - `scripts/eks/benchmark_vllm.py:101-106` — `empty_metric_summary()` — return this on exception
  - `scripts/eks/benchmark_vllm.py:291-300` — the placeholder `kv_cache_metrics` and `queue_pressure_metrics` dicts; replace with fetched values
  - `scripts/eks/benchmark_vllm.py:163-173` — `build_single_run_summary()` — already references `kv_cache_usage_percent` and `requests_waiting`; no changes needed there once values are populated

  **API/Type References**:
  - vLLM Prometheus metric names (Prometheus text format, no external lib needed):
    - `vllm:gpu_cache_usage_perc` — GPU KV cache usage %
    - `vllm:cpu_cache_usage_perc` — CPU KV cache usage %
    - `vllm:num_requests_running` — currently running requests
    - `vllm:num_requests_waiting` — requests in queue
  - Prometheus text exposition: lines like `metric_name{labels} value timestamp` — parse with simple string split, ignore `#` comment lines

  **Acceptance Criteria**:
  - [ ] `grep -n 'metrics_url' scripts/eks/benchmark_vllm.py | grep -v '#'` shows active (non-commented) HTTP fetch call
  - [ ] `grep '_fetch_prometheus_metrics' scripts/eks/benchmark_vllm.py` exits 0
  - [ ] Function handles `urllib.error.URLError` without raising (try/except wraps the fetch)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: _fetch_prometheus_metrics returns empty summaries on connection refused
    Tool: Bash
    Preconditions: no server running on localhost:19999
    Steps:
      1. Run: python3 -c "
           import sys; sys.path.insert(0, 'scripts/eks')
           from benchmark_vllm import _fetch_prometheus_metrics, empty_metric_summary
           result = _fetch_prometheus_metrics('http://127.0.0.1:19999/metrics')
           assert result['kv_cache_metrics']['kv_cache_usage_percent'] == empty_metric_summary(), result
           print('PASS')"
      2. Assert output is 'PASS'
    Expected Result: no exception raised; empty summaries returned
    Failure Indicators: any exception, or AssertionError
    Evidence: .sisyphus/evidence/task-8-metrics-fallback.txt

  Scenario: benchmark_vllm.py output JSON has kv_cache_metrics fields (not all null)
    Tool: Bash (requires a running vLLM endpoint — TIER-2: mark as skipped if no cluster)
    Preconditions: [TIER-2: requires live EKS with port-forward active on METRICS_PORT]
    Steps:
      1. Port-forward metrics port (18001 → 9090)
      2. Run a single benchmark call with --metrics-url http://127.0.0.1:18001/metrics
      3. Check output JSON: kv_cache_metrics.kv_cache_usage_percent.latest is not null
    Expected Result: at least one metric field is non-null in output
    Failure Indicators: all metric fields remain null despite endpoint being reachable
    Evidence: .sisyphus/evidence/task-8-metrics-populated.json
  ```

  **Commit**: YES (group Wave-2-pipeline)
  - Message: `fix(benchmark): wire metrics_url to fetch KV cache and queue pressure from Prometheus`
  - Files: `scripts/eks/benchmark_vllm.py`

---

- [ ] 9. render-experiment-graphs.py — fix EXPERIMENT_DIR silent cwd fallback

  **What to do**:
  - In `scripts/eks/render-experiment-graphs.py` line 606: `exp_dir = Path(os.environ.get("EXPERIMENT_DIR", ""))` followed by `if not exp_dir:` check (line 607)
  - The bug: `Path("")` is truthy in Python (`bool(Path("")) == True`) so the `if not exp_dir` guard never triggers and the script silently uses cwd
  - Fix: change line 606 to `exp_dir_str = os.environ.get("EXPERIMENT_DIR", "")` then check `if not exp_dir_str:` and only set `exp_dir = Path(exp_dir_str)` after the guard

  **Must NOT do**:
  - Do NOT add argparse or CLI arg changes — env var is the intended interface
  - Do NOT change any other path resolution logic below line 609

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 2-line fix, well-understood Python bug
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `scripts/eks/render-experiment-graphs.py:606-609` — the exact buggy block to fix

  **Acceptance Criteria**:
  - [ ] Running `python3 scripts/eks/render-experiment-graphs.py` without `EXPERIMENT_DIR` set prints `ERROR: EXPERIMENT_DIR env var not set.` and exits non-zero
  - [ ] `python3 -c "from pathlib import Path; p=Path(''); print(bool(p))"` outputs `True` (confirms the bug exists before fix)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: Script exits with error when EXPERIMENT_DIR not set
    Tool: Bash
    Preconditions: EXPERIMENT_DIR env var is NOT set in shell
    Steps:
      1. Run: unset EXPERIMENT_DIR; python3 scripts/eks/render-experiment-graphs.py; echo "exit:$?"
      2. Assert output contains 'ERROR: EXPERIMENT_DIR'
      3. Assert exit code is non-zero (1)
    Expected Result: script prints error and exits 1
    Failure Indicators: script runs without error or uses cwd silently
    Evidence: .sisyphus/evidence/task-9-graphs-exp-dir.txt
  ```

  **Commit**: YES (group Wave-2-pipeline)
  - Message: `fix(graphs): prevent silent cwd fallback when EXPERIMENT_DIR is unset`
  - Files: `scripts/eks/render-experiment-graphs.py`

---

- [ ] 10. lane.sh — harden JSON generation against unguarded numeric interpolation

  **What to do**:
  - In `scripts/eks/lane.sh`, the `run-metadata.json` heredoc (lines 120-140) and `scenario-metadata.json` heredoc (lines 187-208) interpolate shell vars like `${tp}`, `${pp}`, `${dp}`, `${max_model_len}`, `${gpu_mem}`, `${network_peak_bandwidth_gbps}` directly into JSON numeric fields
  - The fragility: if any of these vars are empty strings (e.g., `config_value` returns nothing), the JSON becomes invalid (`"tensor_parallel_size": ,`)
  - Fix: for each numeric field, wrap the interpolation with a default-to-zero guard using `${var:-0}` (or `${var:-null}` for fields that can be null). Specifically update `${tp}`, `${pp}`, `${dp}`, `${max_model_len}` in both heredoc blocks
  - For `${gpu_mem}` (float): use `${gpu_mem:-0.0}`
  - For `${network_peak_bandwidth_gbps}` (float): use `${network_peak_bandwidth_gbps:-0}`
  - For `${cluster_nodes_json}` (already a JSON array): use `${cluster_nodes_json:-[]}`

  **Must NOT do**:
  - Do NOT rewrite the heredoc format or switch to jq — fix fragility in-place
  - Do NOT change string fields (those already have quotes as protection)
  - Do NOT change the JSON schema or add/remove fields

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Requires careful reading of both heredoc blocks and applying consistent guarding without breaking valid cases
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `scripts/eks/lane.sh:120-140` — `run-metadata.json` heredoc with unguarded numeric vars
  - `scripts/eks/lane.sh:187-208` — `scenario-metadata.json` heredoc with same issue
  - Bash default-value syntax: `${var:-default}` is safe and idiomatic for this fix

  **Acceptance Criteria**:
  - [ ] `grep '\${tp}\|\${pp}\|\${dp}' scripts/eks/lane.sh` returns 0 matches (bare vars replaced with guarded forms)
  - [ ] `bash -n scripts/eks/lane.sh` exits 0 (syntax valid)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: JSON generation with empty config vars produces valid JSON
    Tool: Bash
    Steps:
      1. Run: bash -c 'tp=""; pp=""; dp=""; max_model_len=""; gpu_mem=""; network_peak_bandwidth_gbps=""; cluster_nodes_json=""; source scripts/eks/lane.sh --dry-run 2>/dev/null || true'
      2. More precisely: extract just the heredoc block and pipe to python3 -m json.tool to validate
      3. Specifically: bash -c 'tp="${tp:-0}"; pp="${pp:-0}"; dp="${dp:-0}"; max_model_len="${max_model_len:-0}"; gpu_mem="${gpu_mem:-0.0}"; network_peak_bandwidth_gbps="${network_peak_bandwidth_gbps:-0}"; cluster_nodes_json="${cluster_nodes_json:-[]}"; echo "{\"tensor_parallel_size\": ${tp}, \"pipeline_parallel_size\": ${pp}}"' | python3 -m json.tool
      4. Assert python3 -m json.tool exits 0
    Expected Result: valid JSON output even with empty vars
    Failure Indicators: json.tool reports parse error
    Evidence: .sisyphus/evidence/task-10-lane-json-guard.txt

  Scenario: bash syntax check passes
    Tool: Bash
    Steps:
      1. Run: bash -n scripts/eks/lane.sh; echo "exit:$?"
      2. Assert exit code is 0
    Expected Result: no syntax errors
    Failure Indicators: bash -n reports syntax error
    Evidence: .sisyphus/evidence/task-10-lane-syntax.txt
  ```

  **Commit**: YES (group Wave-2-pipeline)
  - Message: `fix(lane): guard numeric JSON fields against empty-var interpolation`
  - Files: `scripts/eks/lane.sh`

---

- [ ] 11. python3.11 → python3 sweep across all scripts/eks/*.sh

  **What to do**:
  - Replace every occurrence of `python3.11` with `python3` in all `.sh` files under `scripts/eks/`
  - Confirmed affected files (from audit): `scripts/eks/benchmark-dynamo-vllm.sh` (lines 23, 54, 56, 63), `scripts/eks/benchmark-ray-vllm.sh` (same pattern)
  - Check all other `.sh` files in `scripts/eks/` for any remaining `python3.11` references and replace

  **Must NOT do**:
  - Do NOT change any Python script (`.py`) — they use shebangs `#!/usr/bin/env python3` which is already correct
  - Do NOT change `python3` or `python3.X` references in Dockerfiles or requirements files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Pure sed-style string replacement across shell scripts
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `scripts/eks/benchmark-dynamo-vllm.sh:23,54,56,63` — confirmed `python3.11` occurrences
  - `scripts/eks/benchmark-ray-vllm.sh` — check for same pattern

  **Acceptance Criteria**:
  - [ ] `grep -r 'python3\.11' scripts/eks/` returns 0 matches
  - [ ] `bash -n scripts/eks/benchmark-dynamo-vllm.sh` exits 0

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: No python3.11 references remain in scripts/eks/
    Tool: Bash
    Steps:
      1. Run: grep -r 'python3\.11' scripts/eks/; echo "matches:$?"
      2. Assert grep exits 1 (no matches found)
    Expected Result: zero occurrences of python3.11 in any .sh file
    Failure Indicators: any match returned
    Evidence: .sisyphus/evidence/task-11-python3-sweep.txt
  ```

  **Commit**: YES (group Wave-2-pipeline)
  - Message: `fix(scripts): replace python3.11 with python3 for portability`
  - Files: `scripts/eks/*.sh` (any that contained python3.11)

---

- [ ] 12. Dynamo disagg.yaml.tpl — scaffold Prefill+Decode disaggregated template

  **What to do**:
  - Create `.eks/dynamo/vllm/disagg.yaml.tpl` as a new `DynamoGraphDeployment` manifest with three service components: `PrefillWorker`, `DecodeWorker`, and `Frontend`
  - Model the structure closely after `agg.yaml.tpl` but split the worker into two separate components
  - `PrefillWorker` and `DecodeWorker` both use the same `python3 -m dynamo.vllm` command with all the same args as agg (including `--pipeline-parallel-size ${pipeline_parallel_size}`, `--tensor-parallel-size ${tensor_parallel_size}`)
  - Add the NIXL/KV-transfer flags as **commented-out** lines with a clear gate comment:
    ```yaml
    # EXPERIMENTAL: KV-transfer config for disaggregated prefill/decode
    # Uncomment when disagg mode is stable and NIXL is validated
    # --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_producer"}'  # PrefillWorker
    # --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_consumer"}'  # DecodeWorker
    ```
  - Add a KVBM gate comment block at the top of the file:
    ```yaml
    # UNSTABLE: KVBM (KV Block Manager) integration — do NOT enable
    # Blocked by upstream crash bug: https://github.com/ai-dynamo/dynamo/issues/5857
    # Enable when #5857 is fixed
    ```
  - Reuse all existing template vars from `agg.yaml.tpl` — no new vars needed
  - Both worker types share the model cache PVC mount and HF token secret

  **Must NOT do**:
  - Do NOT enable KVBM — scaffold and comment only
  - Do NOT wire KV-routing into the Frontend component — leave Frontend identical to agg.yaml.tpl
  - Do NOT create a separate `inference_config.py` render path for disagg yet — it can share the `dynamo-vllm` lane vars

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: New file creation requiring understanding of Dynamo's disaggregated architecture and NIXL flag structure
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: Task 4 (agg.yaml.tpl should be correct before disagg is modeled after it)

  **References**:

  **Pattern References**:
  - `.eks/dynamo/vllm/agg.yaml.tpl:1-112` — copy the entire structure; split VllmWorker into PrefillWorker + DecodeWorker
  - `.eks/dynamo/vllm/agg.yaml.tpl:87-100` — worker command args block to replicate in both worker types
  - `.eks/dynamo/README.md` — confirms intended structure and Ansible contract (lane must expose `/health`, `/v1/models`, Prometheus scrape target)

  **External References**:
  - NIXL `--kv-transfer-config` arg: documented in NVIDIA Dynamo vLLM backend docs; format is JSON string passed as CLI arg to `python3 -m dynamo.vllm`
  - Dynamo disaggregated P/D concept: Prefill worker handles prompt processing (KV producer), Decode worker handles autoregressive generation (KV consumer)

  **Acceptance Criteria**:
  - [ ] `ls .eks/dynamo/vllm/disagg.yaml.tpl` exits 0
  - [ ] `grep 'PrefillWorker' .eks/dynamo/vllm/disagg.yaml.tpl` exits 0
  - [ ] `grep 'DecodeWorker' .eks/dynamo/vllm/disagg.yaml.tpl` exits 0
  - [ ] `grep 'UNSTABLE.*5857\|5857.*UNSTABLE' .eks/dynamo/vllm/disagg.yaml.tpl` exits 0 (KVBM gate comment present)
  - [ ] `grep -v '^#\|^\s*#' .eks/dynamo/vllm/disagg.yaml.tpl | grep 'kvbm\|KVBM\|kv_connector\|NixlConnector'` returns 0 matches (no uncommented KVBM/NIXL lines)

  **QA Scenarios (MANDATORY)**:
  ```
  Scenario: disagg template file exists and contains both worker types
    Tool: Bash
    Steps:
      1. Run: cat .eks/dynamo/vllm/disagg.yaml.tpl | grep 'Worker:'
      2. Assert output contains 'PrefillWorker:' and 'DecodeWorker:'
    Expected Result: both worker component names present
    Failure Indicators: file missing or only one worker type found
    Evidence: .sisyphus/evidence/task-12-disagg-workers.txt

  Scenario: KVBM and NIXL flags are commented out (not active)
    Tool: Bash
    Steps:
      1. Run: grep -v '^\s*#' .eks/dynamo/vllm/disagg.yaml.tpl | grep -i 'kvbm\|NixlConnector\|kv_connector'
      2. Assert output is empty (exit code 1 from grep — no uncommented matches)
    Expected Result: all KVBM/NIXL references are in comments only
    Failure Indicators: any uncommented line containing these patterns
    Evidence: .sisyphus/evidence/task-12-disagg-kvbm-gated.txt
  ```

  **Commit**: YES (group Wave-2-dynamo)
  - Message: `feat(dynamo): scaffold disaggregated prefill/decode template with KVBM/NIXL gates`
  - Files: `.eks/dynamo/vllm/disagg.yaml.tpl`
## Final Verification Wave

- [ ] F1. **Bakeoff Readiness Audit** — `oracle`
  Read this plan end-to-end. For each "Must Have": verify implementation exists (read file, grep). For each "Must NOT Have": search codebase for forbidden patterns. Check that both lanes can be invoked via `ansible-playbook experiment.yml -e lane=<lane>` and will produce `benchmark-<lane>.json`.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Template Render Verification** — `quick`
  Run `python3 scripts/eks/inference_config.py` for both lanes. Capture rendered outputs. Verify: (1) Dynamo worker args contain `--pipeline-parallel-size 2`, (2) Ray head template declares containerPort 8080, (3) disagg.yaml.tpl renders without substitution errors.
  Output: `Ray [PASS/FAIL] | Dynamo-agg [PASS/FAIL] | Dynamo-disagg [PASS/FAIL] | VERDICT`

- [ ] F3. **Guardrail Compliance** — `quick`
  Grep for forbidden patterns: `grep -r 'kvbm\|enable.*kv.*cache\|KVBM' .eks/dynamo/` must show only commented lines. `grep -r '8000' scripts/eks/benchmark-dynamo-vllm.sh` must return 0 matches (port 8000 hardcode removed). `grep 'python3.11' scripts/eks/` must return 0 matches.
  Output: `KVBM gated [PASS/FAIL] | Port 8000 removed [PASS/FAIL] | python3.11 removed [PASS/FAIL] | VERDICT`

---

## Commit Strategy

- **Wave 1**: `fix(ray): metrics port, worker monitoring, autoscaling params, version alignment`
- **Wave 1 (dynamo)**: `fix(dynamo): pass pipeline_parallel_size to worker, fix metrics port-forward`
- **Wave 1 (infra)**: `fix(infra): add g7e-1x2 tfvars, node_group_taints variable, destroy auto-approve`
- **Wave 2**: `fix(pipeline): wire metrics_url in benchmark, fix EXPERIMENT_DIR, harden lane.sh JSON, python3 portability`
- **Wave 2 (dynamo)**: `feat(dynamo): scaffold disaggregated prefill/decode template`
- **Wave 3**: `fix(ansible): multi-run loop, EXPERIMENT_DIR threading, cleanup scope`
- **Wave 3 (dynamo)**: `docs(dynamo): document NIXL and KV-routing integration points in agg.yaml.tpl`

---

## Success Criteria

### Verification Commands
```bash
# Both must succeed without errors
python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane ray-vllm --output-root .eks/rendered
python3 scripts/eks/inference_config.py --config .eks/inference-profile.json --lane dynamo-vllm --output-root .eks/rendered

# Dynamo PP fix verified
grep 'pipeline-parallel-size' .eks/rendered/dynamo/vllm/agg.yaml  # Expected: --pipeline-parallel-size 2

# Ray metrics port verified
grep 'containerPort: 8080' .eks/rendered/ray/ray-vllm-service.yaml  # Expected: match

# Disagg template exists
ls .eks/dynamo/vllm/disagg.yaml.tpl  # Expected: file exists

# No python3.11 hardcoding
grep -r 'python3\.11' scripts/eks/  # Expected: no output

# Metrics URL wired
grep -n 'metrics_url' scripts/eks/benchmark_vllm.py | grep -v '#'  # Expected: active usage
```

### Final Checklist
- [ ] Both lanes render templates cleanly
- [ ] Dynamo worker args include PP
- [ ] Ray workers scraped by Prometheus
- [ ] benchmark_vllm.py produces KV cache metrics in output JSON
- [ ] render-experiment-graphs.py requires explicit EXPERIMENT_DIR arg (no silent cwd fallback)
- [ ] disagg.yaml.tpl exists with KVBM/NIXL flags commented + warning
- [ ] Multi-run works: `ansible-playbook experiment.yml -e run_count=3`
- [ ] EXPERIMENT_DIR present in lane_benchmark.yml and lane_validate.yml env blocks
