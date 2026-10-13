# Deferred Optimizations (not implemented in V1)

V1 prioritises correctness, verified integration with the frozen numeric RTL, and a fair D2/E-lite comparison. None of the items below is needed for correctness.

| # | Optimization | Why deferred | Prerequisite / cost |
|---|---|---|---|
| 1 | **Horizontal-interpolation reuse** (share `top`/`bottom` across events with the same `(grid, x, y>>5)`) | `wm_lerp` computes `top`/`bottom` internally (18-bit, unsaturated) and does not port them. Sharing would require splitting Codex's frozen `wm_lerp`/`wm_mapper_lane` | A Codex-owned interface change (e.g. a lane variant with `top/bottom` inputs) plus re-verification. V1 implements **node-fetch / address reuse only** |
| 2 | Node "slide-down" fetch (reuse the bottom node pair when only gy advances) | Logical read-bandwidth refinement only. V1's cell-key reuse already serves 81 % of lane node sets without a grid read on the real subset | Matters only for a real 2R1W macro |
| 3 | **Grid storage macro / register file** | V1 uses an async-read behavioural array (2 × 744 × 48 b, 4 parity sub-banks, 2 read ports per sub-bank) so it can be swapped | A sync-read macro needs one extra pipeline stage before the L stage. The metadata pipe is unchanged; the D stage gains one register |
| 4 | Single-buffer grid (`GRID_BUFS = 1`) | Halves grid storage (−35,712 b) but needs a load gap at each frame | Decide after PPA shows the grid store's share of area |
| 5 | **Direct-bin ray quantizer** (Exp05b candidate: 62 thresholds, no CORDIC/isqrt) | Not the frozen V1 method; numeric RTL is Codex-owned | Codex experiment + new numeric RTL; would change lane latency (metadata pipe parameter only) |
| 6 | Alternative bank hash (`XOR_PLAIN`) | Exp05b re-screen showed XOR_NEG ≈ XOR_PLAIN; frozen contract is XOR_NEG | `bank_of()` in `wm_ctrl_pkg` is the single point of change |
| 7 | **FIFO depth from true burst timing** | 128 words is an engineering start; DELTA data has only per-frame timestamps | Needs intra-frame arrival timing (sensor spec or adapter measurement) |
| 8 | Cross-word dispatch pairing (`DISPATCH_MODE = STREAM`) | Word-local pairing measured 0.914 issue efficiency on the real subset; STREAM would add cross-word group bookkeeping | Only if the post-synthesis clock leaves < ~10 % margin |
| 9 | Queue-tail fold (merge across groups at bank-queue enqueue) | Would change RMW counts vs the Exp05b consecutive-merge reference (memory contents identical) | Optional energy optimization after V1 sign-off |
| 10 | FRAME_MARK transaction and LATEST grid policy | V1 binds frames by per-word `frame` id with STRICT policy (stall on missing grid) | Needed only for real-time operation with late pose |
| 11 | Sensor adapter (raw DELTA words → `nword_t`) | Outside the measured core boundary; testbench builds native words from decoded data | Thin RTL block (column register + field extraction) |
