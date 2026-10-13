# Synthesis Comparison Plan (first PPA)

Goal: isolate what E-lite costs and buys, with everything else held equal. Flow and honesty rules follow Stage 1:
- Genus, GPDK045 slow corner;
- one clock constraint for all builds;
- the same SDC including explicit I/O delay;
- report "pre-layout" status.

## Builds

| Build | Parameters | Purpose |
|---|---|---|
| **BASELINE-HW (D2)** | `N_LANES=2, HCACHE_EN=0, MERGE_EN=0` (merger generate-removed), same router/banks/FIFO/grid store | Per-event two-lane mapper |
| **PROPOSED-HW (E-lite)** | `HCACHE_EN=1, HCACHE_XLANE=1, MERGE_EN=1, MERGE_THRESH=2, MERGE_SCOPE=GROUP` | Frozen V1 |
| Variant G1 (optional) | E-lite with `GRID_BUFS=1` | Grid-storage area sensitivity |
| Variant Q (optional) | E-lite with `QUEUE_FOLD=1` | Extra merge at queue tail |

Held identical across builds:
- the T32 lane datapath and fixed-point formats (Codex Exp05);
- the ray→angle unit;
- `wm_addr_gen` and the bank function;
- the 4-bank router;
- `BQ_DEPTH`, `FIFO_DEPTH_WORDS`;
- the memory word format (4×4-cell tile words in **both** builds, so the logic difference is not confounded by memory organisation);
- the clock constraint and I/O delays.

## Synthesis boundary

| Item | Synthesized? | Reported how |
|---|---|---|
| FIFO, unpacker, frame ctrl, lanes, hcache, skid, merger, router, bank controllers, status | yes | Area, timing, power by hierarchy (`report_area -depth`, as Stage 1 did for Model2) |
| Grid store (2 × 744 nodes) | yes (flop array) | Reported **separately** in the hierarchy. It is likely the largest block and is identical in both builds |
| World memory banks | **no** (`wm_mem_model` is a simulation-only behavioural model; the top is synthesized with the memory ports as top-level I/O or a black box) | Separate estimate: words × width per bank, accesses (RMW count from simulation) × per-access energy from a **cited** source (e.g. OpenRAM/FreePDK45 proxy, stated as a different PDK) |
| Testbench, decoders, grid generator | no | — |

## Metrics to report

1. Logic area per hierarchy block (D2 vs E-lite delta = hcache + merger + record-width growth).
2. Pre-layout Fmax (period sweep, as in Stage 1), with the critical path identified. Likely candidates: the ray→angle unit, `wm_lerp`, and the bank modify stage (bypass mux + saturating adders).
3. **Activity-based power on real traces.** VCD/SAIF from L6 replay of the same frames for both builds. This is where hcache benefits show (node reads and lerp toggles avoided).
4. Simulation-derived counts: RMWs per event, node reads per event, stall cycles, FIFO high-water mark, frame lag.
5. Combined: logic energy/event + memory energy/event (estimated), at the same delivered events.

## What a fair conclusion can say

- "E-lite reduces memory RMWs by X % and node reads by Y % on these traces, at a logic-area cost of Z % and a logic-power change of W % (activity-based)."
- It must **not** claim total-system savings beyond what the cited memory energy model supports, and must state that memory is not synthesized.
