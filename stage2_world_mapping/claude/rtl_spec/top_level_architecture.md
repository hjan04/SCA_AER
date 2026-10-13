# Top-Level Architecture

## Block diagram

```
                      grid load port (from SW/TB: node_idx, ray xyz, commit(epoch))
                                   │
                         ┌─────────▼──────────┐     ┌──────────────┐
                         │  wm_grid_store     │◄────│ wm_frame_ctrl│ (active buf, epochs,
                         │  2 bufs × 4 parity │     │              │  in-flight counters)
                         │  sub-banks, 2 lane │     └──────▲───────┘
                         │  read ports        │            │ frame_id of head word
                         └──┬──────────────┬──┘            │
 sensor word ─► wm_input_fifo ─► wm_word_unpacker ─(bundle ≤2 events, lock-step)─┐
 (valid/ready)   (words)          (2 priority encoders)                          │
                                                                                  ▼
                        ┌──────────────────── wm_mapper_lane[0], [1] ────────────────────┐
                        │ S1 key+hcache lookup ─ S2 node read ─ S3 H-lerp ─ S4 V-lerp ─   │
                        │ S5.. ray→angle (L_ANG) ─ Sq quant/wrap/clamp ─ Sa addr gen      │
                        └───────────────┬────────────────────────────────────────────────┘
                              wm_hcache (2-entry, shared by both lanes)
                                        │ 2 mapped events/cycle
                                  wm_out_skid (2-entry skid, registered ready)
                                        │
                                  wm_elite_merger (1 open record; ≤2 records/cycle)
                                        │
                                  wm_bank_router (2 → 4, dual-enqueue bank queues)
                    ┌──────────┬────────┴─┬──────────┐
              wm_bank_ctrl[0] [1]        [2]        [3]   (RMW + RAW bypass + sat add)
                    │          │          │          │
              wm_mem_model[0..3] (behavioural, not synthesized)

 wm_status: counters tapped from every block
```

## Design principles

1. **The transaction is a native word, not an event.** Grouping that the sensor already performed is preserved up to the mapper and the merger (`module_interfaces.md` §1).
2. **Lock-step lanes, fixed latency, in order.** Both lanes advance on one enable. Mapped events leave in dispatch order, which is what makes the reuse cache and the run-merger simple and deterministic.
3. **Commutative accumulation everywhere downstream.** No reorder buffer exists. Records to different banks may complete in any order. Per-bank FIFO order plus RAW bypass guarantee per-word correctness.
4. **Per-frame state switches without draining.** Each event carries a 1-bit grid-buffer select. Only the grid buffer itself must be drained before it is reloaded (`frame_epoch_protocol.md`).
5. **No associative structures beyond ≤ 4-entry compares.** These are the 2-entry hcache, the 1-entry open record, and the RD_LAT+1-entry bypass per bank.
6. **D2 baseline = the same RTL with `MERGE_EN=0, HCACHE_EN=0`.** Both builds share all other modules, which keeps the synthesis comparison fair (`synthesis_comparison_plan.md`).

## Parameter overview

| Parameter | Owner | Default / status |
|---|---|---|
| `IMG_W, IMG_H` | arch | 960, 720 |
| `GRID_T` | arch (frozen) | 32 → `GRID_NX=31`, `GRID_NY=24` |
| `GRID_NODE_W` | Codex | WAITING_FOR_CODEX_EXP05 (draft: 16, Q1.15, ×3 components) |
| `LERP_DELTA_W, LERP_PROD_W, LERP_ACC_W` | Codex | WAITING_FOR_CODEX_EXP05 (draft: 17 / 22 / 17) |
| `RAY_W` | Codex | WAITING_FOR_CODEX_EXP05 (draft: 16) |
| `ANGLE_W, ANG_ITERS, L_ANG` | Codex + arch | WAITING_FOR_CODEX_EXP05 (ray→angle contract) |
| `WORLD_W, WORLD_H` → `WORLD_X_W, WORLD_Y_W` | Codex | WAITING_FOR_CODEX_EXP05 (draft: 256×128 → 8, 7) |
| `TILE_W, TILE_H` (cells per memory word) | Codex + arch | WAITING_FOR_CODEX_EXP05 (Exp04/05 proxy: 4×4) |
| `CNT_W` (per cell, per plane) | Codex | WAITING_FOR_CODEX_EXP05 |
| `ACC_MODE` | arch | `UNSIGNED` (V1 default) / `ONOFF_PACKED` |
| `N_LANES` | arch (frozen) | 2 |
| `N_BANKS` | arch (frozen) | 4 |
| `BANK_FN` | Codex + arch | XOR family at **tile** level: WAITING_FOR_CODEX_EXP05 confirmation (`banked_memory.md`) |
| `FIFO_DEPTH_WORDS` | arch | 128 (initial; not proven against real burst timing) |
| `BQ_DEPTH` (per-bank queue) | arch | 4 (initial) |
| `RD_LAT` | arch (memory model) | 1 (sweep 1..3 in verification) |
| `HCACHE_EN, HCACHE_ENTRIES` | arch | 1, 2 |
| `MERGE_EN, MERGE_THRESH, MERGE_SCOPE` | arch | 1, 2, `GROUP` |
| `GRID_POLICY` | arch | `STRICT` (V1) / `LATEST` |
| `DISPATCH_MODE` | arch | `WORD_LOCAL` (V1) / `STREAM` |
| `FRAME_ID_W` | arch | 8 |
