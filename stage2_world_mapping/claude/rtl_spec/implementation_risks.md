# Implementation Risks: Deadlock / Loss / Correctness Review

| # | Risk | Where | Mechanism | Mitigation in this spec | Residual |
|---|---|---|---|---|---|
| 1 | Dropped events | FIFO, unpacker | Overflow, or invalid coordinates | Core never drops: back-pressure only. Invalid coordinates counted. Conservation invariant | A non-stallable real sensor still overflows upstream if bursts exceed FIFO + slack. **FIFO depth unproven** without intra-frame timing |
| 2 | Ready/valid combinational loop | skid ↔ lanes ↔ merger ↔ router | `ready` derived from `valid` through several blocks | Registered `ready` at the skid. Router accept depends only on queue state + record targets. Rule "valid never from ready" | Must lint |
| 3 | Global-stall timing | `adv` fan-out to ~2 × (6 + L_ANG) wide regs | Large fan-out net | Registered at the skid; buffer tree from synthesis | Fmax impact to be measured |
| 4 | Bank starvation | router / queues | — | Single source, per-bank independent dequeue, FIFO order | None identified |
| 5 | Router livelock | atomic pair accept | A queue never frees | Banks always drain when `mem_ready`. Memory model must eventually assert ready | Depends on the real memory interface |
| 6 | Frame/grid race | frame ctrl, grid store | Reload while referenced; stale hcache after reload | Buffer release only after the S0..S2 reference drain; hcache invalidated by `gsel` at release; writes only to FREE/LOADING | Verify with L1 FSM + L6 multi-frame |
| 7 | Grid never arrives | STRICT policy | Loader late or missing | `grid_wait_cycles`, `grid_timeout` flag; `LATEST` policy as fallback | System-level decision on pose latency |
| 8 | Memory RAW hazard | bank ctrl | Read before an older same-word write | Write-history bypass (depth `RD_LAT`, youngest match) | Must be verified at RD_LAT 1..3 |
| 9 | Merge double counting | merger | Record emitted twice under stall, or event folded and also emitted | Output regs hold until atomic accept; fold and emit are exclusive per event; invariant Σ n_events | — |
| 10 | Polarity corruption | merger, bank (ONOFF) | Wrong plane, or merge across modes | Record carries separate `delta`/`delta_off`; signed mode not supported | — |
| 11 | Saturation hiding loss | bank | Count invariant fails at saturation | Saturation counter; invariant only for unsaturated cells | `CNT_W` choice (Codex) |
| 12 | hcache stale hit | hcache | Data overwritten before follower reads | In-order fixed latency, write and read at S3; shadow-recompute assertion in simulation | — |
| 13 | Issue-rate margin | dispatch | Worst measured frame uses 90.3 % of the 100 MHz budget | `DISPATCH_MODE = STREAM` (→ 81 %), FIFO slack | If Fmax < ~91 MHz, word-local dispatch misses the worst frame. Must re-check after synthesis |
| 14 | Bank-function assumption | addr gen | Exp04 banking measured at cell level, not tile level | `BANK_FN` parameter; request a Codex tile-level re-screen | Unmeasured |
| 15 | Ray→angle contract missing | lane | Address-level bit-exactness impossible | Ray-code bit-exactness first. Contract request to Codex | **Blocking for L2 address checks** |
| 16 | Run-merge ≠ reference set-merge | merger | RMW counts differ (maps equal) | Request a `run` mode in Codex's reference; compare maps always | Minor |
| 17 | Grid storage area | grid store | 2 × 35.7 kbit flops | Separate hierarchy reporting; `GRID_BUFS = 1` variant | Likely the largest area item |
| 18 | Peak-window burst | FIFO | 201 k events per 1 ms window > ~180 k effective capacity | Back-pressure + FIFO; report the high-water mark from non-stallable replay | Needs real intra-frame timing |
