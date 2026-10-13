# Final Stage 2 Architecture (V1, frozen)

Status: **frozen for submission.** No RTL redesign is recommended before the report. Files and hashes: current `rtl/` tree. `wm_mapper_lane.sv` = `5499e67f…`, `wm_ctrl_pkg.sv` = `3296e87c…` (Round 2). Every other RTL file matches `MANIFEST.md`.

## Datapath

```
native sensor word (column x, ≤2 groups of 8-pixel mask, polarity, frame id)
  -> input FIFO (128 x 52 b, flops)                    [param FIFO_DEPTH]
  -> unpacker: <=2 events/cycle, invalid pixels dropped and counted
  -> D stage: bind event to active grid buffer (gsel)
  -> L stage: node fetch with cell-key reuse (node-fetch only)  [REUSE_EN]
  -> 2 x mapper lane, II = 1, 53 enabled edges:
       3 x nested lerp (Q1.15, 5-bit offsets, RNE)
       -> registered ray boundary (Round 2)
       -> isqrt28 (x^2+z^2) || CORDIC24 azimuth -> CORDIC24 elevation (BAM32)
       -> world quant 256 x 128 (wrap x, clamp y)
     + 2 x 53-stage metadata pipes on the same global CE
  -> output buffer (4 bundles; full => global mapper_ce = 0)
  -> E-lite merger: consecutive-only, same frame + native group + bank + tile word  [MERGE_EN]
  -> 4-bank router (XOR_NEG), atomic pair accept
  -> 4 x bank RMW controller (queue 4, RAW bypass, RD_LAT param, 4-bit ON/OFF saturating)
  -> 4 x 512 x 128 b world memory (black box in synthesis)
```

## Frozen parameters and how strongly each is justified

| Item | Value | Justification strength | Report as |
|---|---|---|---|
| Geometry | T32 warp grid, 31 × 24 nodes | Strong vs PWL (general pose); moderate vs T64 | "Selected for bin-edge margin and headroom at 35.7 kbit/buffer" |
| Number format | signed Q1.15 grid/ray, 5-bit offsets, RNE | Measured knee (Exp05 sweep) | "Knee of the measured precision sweep" |
| Ray boundary register | after lerp, before ray2angle | Measured (Round 1 → Round 2 timing) | "Single-variable timing fix, II preserved" |
| Ray-to-address | isqrt28 + 2 × CORDIC24 / BAM32 | Verified, regular, positive slack; not area-minimal | "Retained over direct-bin for verification maturity and margin" |
| Lanes | 2, II = 1 | Strong (rates vs 1-lane capacity; 150 MHz fails) | "Required at 100 MHz" |
| Latency | 53 enabled edges | ARCH + verified | — |
| Reuse | node-fetch, key (gsel, gx, gy) | Exactness proven; benefit = 81% fewer grid reads | "Grid-read reduction" |
| Merge | E-lite consecutive-only | Strong (RTL) for throughput; energy unknown | Headline contribution |
| Banks | 4, XOR_NEG | Hash supported; count not swept | "Selected" |
| Map | 256 × 128 equirectangular, 4 × 4 tiles | Application choice | Note the coupling with merge benefit |
| Counters | CNT_W = 4, ON/OFF | Engineering default; saturates on real data | Parameter |
| FIFO | 128 words | Not derived from data | Parameter; unvalidated against bursts |
| Clock | 100 MHz | Closes in slow corner, pre-layout; ceiling ≈111 MHz (indicative) | Target |

## Storage summary (architectural, exact)

| Array | Bits | Ports needed | Synthesized? |
|---|---:|---|---|
| Grid, 2 buffers | 71,424 | 4 parity sub-banks × 2R + 1W (8 node reads/cycle peak) | No (black box) |
| World memory | 262,144 | per bank 1R + 1W per cycle (RMW) | No (black box) |
| Input FIFO | 6,656 | 1R1W | **Yes, as flops** (≈15% of logic area) |

## Logic PPA (Round 2, MODE1, 100 MHz, slow corner, pre-layout)

| | Cell area | Total area | WNS | Vectorless power |
|---|---:|---:|---:|---:|
| D2 (MERGE_EN = 0) | 447,464.934 | 616,352.597 | 0 ps | 33.336 mW |
| **E-lite (selected)** | **493,230.690** | **677,885.514** | **0 ps** | **36.807 mW** |

Includes the flop FIFO (72,345) and verification counters (9,791). Excludes memory arrays and clock tree.

## Explicitly outside the design boundary

- Pose estimation, and generation of the 744-node grid per pose update. The grid is supplied externally.
- Sensor adapter (raw sensor words → `nword_t`).
- Map readout, decay and consumer.
- SRAM macros.

## Future work, in order of documented potential (none for this submission)

1. Direct-bin quantizer. Measured −19% ray-path cell area; projected about −13% system logic, including shorter metadata pipes; fewer bin-edge flips. Needs a system-level integration and verification pass.
2. CORDIC iteration and width reduction, guided by bin-flip rate rather than Golden bit-matching.
3. Horizontal-lerp (arithmetic) reuse, which needs a lane interface change.
4. FIFO in SRAM, sized from true burst timing.
5. Counter decay or windowed clear policy for real-data dynamic range.
