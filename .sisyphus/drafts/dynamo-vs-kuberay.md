# Draft: Dynamo vs KubeRay Comparison & Decision

## Requirements (confirmed)
- Use case: Frequent node shape changes (e.g., g7e.8xlarge ↔ g7e.16xlarge)
- Experimenting with inference workloads on EKS (AWS)
- Model: Qwen3-30B-A3B
- Two lanes already partially implemented in repo: `ray-vllm` and `dynamo-vllm`
- Considering whether Dynamo should replace KubeRay or run in parallel
- Need to understand Dynamo's advanced features vs what's currently wired up

## Scope Boundaries
- INCLUDE: Comparing Dynamo vs KubeRay for this specific use case; identifying gaps in current repo configs; making a recommendation
- EXCLUDE: Full implementation plan for either (that's a separate planning session)

---

## Research Findings

### Current Repo State — Dynamo Lane (from `bg_17fb867d` audit)

**What's implemented:**
- `DynamoGraphDeployment` in aggregated mode (`agg.yaml.tpl`)
- Components: `Frontend` + `VllmWorker`
- Worker runs: `python3 -m dynamo.vllm` with TP, DP, gpu-memory-utilization, max-model-len, block-size, max-num-seqs
- Full metrics coverage: PodMonitor (frontend + worker) + ServiceMonitor — BETTER THAN RAY
- Image: `nvcr.io/nvidia/ai-dynamo/vllm-runtime:0.8.0`
- Parameterization is thorough via `inference_config.py`

**Critical gaps in Dynamo lane:**
1. `pipeline_parallel_size` is in `inference-profile.json` (=2) but NOT passed to worker args in `agg.yaml.tpl` — **PP is silently ignored**
2. No disaggregated prefill/decode configured (no separate prefill/decode worker types)
3. No NIXL or KV cache routing — these are NOT enabled anywhere in templates/scripts
4. `benchmark-dynamo-vllm.sh` has a **port-forward bug**: maps metrics to remote port 8000 (hardcoded), but template/profile uses 9090 — metrics collection will fail
5. `validate-dynamo-vllm.sh` doesn't port-forward metrics at all

**What NIXL/disaggregation would require:**
- Separate `Prefill` + `Decode` worker components in `DynamoGraphDeployment`
- Explicit NIXL flags (no `--nixl` in any template today)
- Different template file (e.g., `disagg.yaml.tpl` would need to be created)

---

### Current Repo State — KubeRay Lane (from `bg_2dc2124e` audit)

**What's implemented:**
- `RayService` with embedded `RayCluster`: head group + gpu-workers group
- Serve app: `ray.serve.llm:build_openai_app`
- TP/PP via `engine_kwargs`: tensor_parallel_size=1, pipeline_parallel_size=2
- PP=2 validated by `validate-ray-vllm.sh` (expects 2 distinct nodes)
- Resources: head + worker each get 8 CPU / 48Gi RAM / 1 GPU (requests)
- RAY_GRAFANA_IFRAME_HOST correctly set to `http://127.0.0.1:3000` ✅
- KubeRay operator installed via Helm (v1.5.1 default)

**Critical gaps in Ray lane:**
1. Metrics port **mismatch**: `ray-metrics-service.yaml` targets port 8080 on head, but RayService template doesn't declare containerPort 8080 — scraping may silently fail
2. Worker pods NOT scraped by any ServiceMonitor/PodMonitor — only head has metrics coverage
3. Serve autoscaling `min_replicas`/`max_replicas` hardcoded to 1 in template (not parameterized)
4. Ray version vs image version mismatch: `ray_version: 2.52.0` in profile but image is `anyscale/ray-llm:2.54.0-py311-cu128`

---

### Known Bugs (from prior audit sessions)

**`benchmark_vllm.py`:**
- Accepts `metrics_url` but never uses it to populate KV cache / queue pressure metrics (lines 291-300 are empty placeholders)

**`render-experiment-graphs.py`:**
- Critical: `EXPERIMENT_DIR` detection uses `Path("")` (truthy) — silently uses cwd (lines 606-609)

**`lane.sh`:**
- Fragile JSON generation with unguarded numeric interpolation (lines 120-139, 187-207)

**Terraform:**
- Missing `terraform.g7e-1x2.tfvars`
- No `node_group_taints` variable

**Ansible:**
- `destroy.sh` missing `-auto-approve` flag — blocks headless runs
- `orchestrate_experiment.yml` only supports single run (no loop for multi-run sessions)
- `EXPERIMENT_TIMESTAMP`/`EXPERIMENT_DIR` inconsistently threaded

---

### External Research (from direct web search)

**Dynamo Architecture (what it actually offers):**
1. **Disaggregated prefill/decode** — separate prefill workers (larger memory, lower latency) and decode workers (higher throughput), each with independent TP sizing
2. **NIXL (NVIDIA Inference Transfer Library)** — direct VRAM-to-VRAM KV cache transfer between nodes, bypassing CPU (non-blocking)
3. **KV-aware routing** — routes incoming requests to workers that already have matching cached KV blocks (prefix caching at routing layer, not just within one worker)
4. **Distributed KV Cache Manager** — offloads KV cache to CPU/SSD/object storage for "infinite" context scaling
5. **SLA-based planner** — dynamically schedules GPU resources based on load/SLA targets
6. **Claims: up to 30x throughput improvement** on DeepSeek-R1 on Blackwell (NVIDIA-sourced claim)

**KubeRay Known Issues:**
- `[Bug]` multi-node PP: non-primary worker pods report unready (kuberay#2552 — open)
- `vLLMDeployment` throughput doesn't scale well with `n_replicas` (Ray#53356 — closed/fixed)
- KubeRay autoscaling with vLLM PP is open feature request (#4099)

---

## Open Questions

1. Are the 1 remaining background agents done? (deep Dynamo research)
2. Does user want a formal plan (work plan file) or just a recommendation/comparison report?
3. Should Ansible adoption be decided now or deferred?
4. What is the user's primary concern: throughput, latency, operational simplicity, or experiment velocity?

---

## Technical Decisions (pending research completion)

- [ ] Dynamo vs KubeRay recommendation — **BLOCKED on 1 remaining agent result**
- [ ] Whether to create `disagg.yaml.tpl` for Dynamo disaggregated mode
- [ ] Whether to fix PP bug in Dynamo template now or after decision

---

## Agent Research Status

| Agent | Task ID | Status |
|-------|---------|--------|
| explore: Dynamo repo audit | `bg_17fb867d` | ✅ consumed |
| explore: KubeRay repo audit | `bg_2dc2124e` | ✅ consumed |
| Sisyphus-Junior (deep): Dynamo research | `bg_d3017c99` | 🔄 running |
| Sisyphus-Junior (deep): KubeRay research | `bg_75d940fa` | ✅ consumed |
| librarian: Dynamo GitHub/docs | `bg_bec3a125` | ✅ consumed |

---

### Librarian Findings — Dynamo Architecture (from `bg_bec3a125`)

**Repo**: `ai-dynamo/dynamo` — 6,224 ⭐, Apache 2.0, v0.8.1 latest, ~1 year old, 3,619 commits
**Docs**: https://docs.nvidia.com/dynamo/
**EKS guide**: `examples/deployments/EKS/` in the repo

**Five core components (confirmed from source):**
1. **Frontend** — Rust-based OpenAI-compatible HTTP server
2. **Router** — Two modes: basic load-balance OR KV-aware (routes to worker with highest KV hit rate) — *3x TTFT improvement, 2x lower avg latency* on 100K R1 queries
3. **Planner** — SLA-based autoscaler, watches event plane, scales prefill/decode workers independently; known bug: cannot scale to zero (#6985)
4. **KVBM** (KV Cache Block Manager) — multi-tier: GPU HBM → CPU DDR → NVMe SSD → Object Storage; *2.2x–12x TTFT improvement* depending on QPS; bug: crashes with KVBM+vLLM (#5857 open)
5. **NIXL** (separate repo `ai-dynamo/nixl`, 923⭐) — C++ library, UCX/RDMA direct GPU-to-GPU KV transfer, non-blocking

**Disaggregated P/D (confirmed ✅ for vLLM):**
- Prefill computes KV cache → NIXL transfers directly VRAM-to-VRAM → Decode continues
- Flow: `kv_transfer_params` (block IDs + remote worker info) passed via vLLM
- *30% throughput/GPU gain (1 node), 2x gain (2 nodes)* on Llama 70B H100
- xPyD topology: x prefill workers, y decode workers, runtime-reconfigurable

**Kubernetes deployment:**
- CRDs: `DynamoGraphDeployment` (DGD), `DynamoGraphDeploymentRecipe` (DGDR)
- **K8s-native**: no etcd/NATS required (uses EndpointSlices natively)
- Helm charts: `deploy/operator/`, observability: `deploy/observability/k8s/`
- Grove: network topology-aware gang scheduling (`ai-dynamo/grove`)

**Published benchmarks (NVIDIA-sourced, may be optimistic):**
- 30x throughput on DeepSeek-R1 671B on GB200 NVL72
- 3x TTFT via KV-aware routing (H100, real R1 queries)
- 2x TTFT on Llama 70B disaggregated 2-node vs aggregated
- Baseten (external): 2x faster inference switching to Dynamo

**Maturity risks / open issues:**
- 520 open issues
- KVBM+vLLM crashes: #5857 (open) — AssertionError with KVBM enabled
- NIXL lifecycle issues: #6671, #6912 — conflicting installations cause crashes
- Multi-node issue: #5719 — Cannot run DGD with vLLM + multiNode + TP*PP > GPU_per_pod
- K8s UX actively being redesigned: #6129, #6717 — docs gaps for production
- Planner cannot scale-to-zero: #6985

**Critical for our use case (frequent node shape changes):**
- Dynamo has NO documented node-shape-aware autoscaling or hot-swap
- Changing node shapes still requires re-deploying the DynamoGraphDeployment
- Grove (gang scheduling) helps with topology-aware placement but is a separate component

---

### KubeRay Deep Research Findings (from `bg_75d940fa`)

**Architecture confirmed:**
- RayService = RayCluster lifecycle + Serve apps; supports in-place Serve updates + blue/green cluster upgrades
- Head participates in TP/PP (requires GPU on head for `vllm serve` in KubeRay PP path)
- Cross-node TP/PP uses Ray placement groups (default `PACK`, spills cross-node as needed)
- Autoscaling updates `replicas`/`workersToDelete` fields in CRD via Ray logical resource demand

**Production pain points (evidence-backed):**
- **GCS is in-memory by default** — head failure kills entire cluster; Redis-backed FT required for HA
  - Source: https://docs.ray.io/en/latest/_sources/ray-core/fault_tolerance/gcs.rst.txt
- **502s during head recovery** in RayService HA path — open P1 issue
  - Source: https://github.com/ray-project/kuberay/issues/1153
- **Head deletion serving failures** even with FT setup contexts (historical)
  - Source: https://github.com/ray-project/kuberay/issues/1463
- **PP autoscaling still uncertain** — user requests open
  - Source: https://github.com/ray-project/kuberay/issues/4099
- **Ray Serve overhead vs bare vLLM** — community reports 2-3x higher latency at high concurrency/streaming
  - Source: https://discuss.ray.io/t/ray-serve-llm-apis-has-2-3x-higher-latency/22356
  - Source: https://github.com/ray-project/ray/issues/59681
  - Ray team added nightly benchmarks to track this regression: https://github.com/ray-project/ray/pull/52607

**Node shape changes with KubeRay:**
- RayService supports zero-downtime new-cluster upgrade when `rayClusterConfig` changes
  - Traffic switches to new head service selector after readiness, old cluster terminated
  - BUT: not all fields trigger blue/green path (autoscaler-managed replica fields are exceptions)
- Shape change = new pods + model reload/warmup → **dominated by image pull + pod scheduling + model load**
- KubeRay does NOT hide Kubernetes node-provisioning latency — only coordinates CRDs + autoscaler

**AWS EKS + Dynamo source:**
- https://aws.amazon.com/blogs/machine-learning/accelerate-generative-ai-inference-with-nvidia-dynamo-and-amazon-eks/

**Key bottom line from researcher:**
> For EKS g7e, run a like-for-like bakeoff (same model, tokenizer, prompt mix, concurrency sweep, streaming/non-streaming, TTFT/P99/throughput) before committing to either path.

---

### Deep Dynamo Research Findings (from `bg_d3017c99`)

**Maturity confirmed:**
- Latest stable: **v0.9.1**, v1.0.0 in progress
- Still pre-1.0, rapid changes, substantial open issue volume
- Support matrix: https://github.com/ai-dynamo/dynamo/blob/main/docs/reference/support-matrix.md

**Architecture clarifications:**
- "Aggregator" in Dynamo = **aggregated serving mode** (prefill+decode together), NOT a separate service
- Disaggregated mode = separate prefill workers + decode workers (requires explicit config)
- Dynamo DOES NOT replace vLLM; typical flow: `Client → Dynamo Frontend/Router → Dynamo vLLM Worker(s) → GPU`

**Ray Serve now also supports PD disaggregation (NEW INFO):**
- Ray Serve added disaggregated serving APIs: https://docs.ray.io/en/latest/serve/llm/architecture/serving-patterns/prefill-decode.html
- Anyscale post on Wide-EP + disagg: https://www.anyscale.com/blog/ray-serve-llm-anyscale-apis-wide-ep-disaggregated-serving-vllm
- This narrows the gap — Ray is NOT fully behind on disaggregation anymore

**Key scheduling difference:**
- **Dynamo**: LLM-specific routing (KV overlap, prefill/decode balancing, SLA-based planner loops)
- **Ray Serve**: general distributed app scheduling with LLM features layered in

**EKS-specific:**
- AWS + NVIDIA official EKS deployment guide exists: https://aws.amazon.com/blogs/machine-learning/accelerate-generative-ai-inference-with-nvidia-dynamo-and-amazon-eks/
- EKS examples in repo: `examples/deployments/EKS/`
- Dynamo K8s operator docs: https://docs.nvidia.com/dynamo/latest/kubernetes/dynamo_operator.html
