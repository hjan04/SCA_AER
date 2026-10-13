# World memory format and replay results

## Address and tile organization

V1 uses a 256 × 128 equirectangular direction map. `world_addr = world_y*256 + world_x`, row-major, 15 bits. A memory word stores a 4 × 4 tile. Coordinates decompose as `tile_x=world_x[7:2]`, `tile_y=world_y[6:2]`, `cell_offset=4*world_y[1:0]+world_x[1:0]`. Each tile is routed with `bank=(tile_x[1:0] XOR ((-tile_y) mod 4))`; local word address is `{tile_y,tile_x[5:2]}` (9 bits). This is Claude's proposed XOR_NEG mapping.

## V1 accumulator recommendation

Use packed ON and OFF saturating counters in each cell, each `CNT_W=4` bits by default, with saturation at 15. One tile word is 16 cells × (4 ON + 4 OFF) = 128 bits; all 2,048 tile words use 262,144 bits total (32 KiB). Keep `CNT_W` an RTL parameter; four bits is an engineering default that allows more accumulated dynamic range than a 2-bit counter, not a competition requirement or a width established by traffic statistics. Do not use signed saturating accumulation. During a merge, keep separate nonnegative per-cell ON and OFF deltas. Apply saturating addition independently to each plane. Because both planes are monotone saturating sums, batching deltas preserves the final contents independent of event order.

## Tile-level bank re-screen

Data: Exp04 finalist frames 1, 65, …, 2049 from each of Claude's three decoded Exp03 caches; source event order, native word and slot are retained. POSE-0 uses identity; POSE-ROLL is a synthetic stress pose, not recovered camera motion. Sept22b uses its Exp04 mapped checkpoint; sept15 and sept22a are mapped from their sampled coordinates with the vectorized floating T32 software model. Bank conflicts count same-bank destinations among cycles with exactly two records, after the consecutive merger for E-lite. Same-bank/same-word pairs are reported separately in `bank_rescreen.csv`.

| Architecture | Bank function | Mean conflict fraction | Mean max/ideal bank load | Bank utilization |
|---|---:|---:|---:|---:|
| D2 | low-bit `tile_x mod 4` | 0.9877 | 1.0983 | 4/4 |
| D2 | `tile_x XOR tile_y` low 2 bits | 0.8690 | 1.0166 | 4/4 |
| D2 | Claude XOR_NEG | 0.8689 | 1.0159 | 4/4 |
| E-lite | low-bit `tile_x mod 4` | 0.9370 | 1.0945 | 4/4 |
| E-lite | `tile_x XOR tile_y` low 2 bits | 0.6702 | 1.0144 | 4/4 |
| E-lite | Claude XOR_NEG | 0.6689 | 1.0150 | 4/4 |

Both XOR mappings substantially outperform low-bit x banking. XOR_NEG and XOR_PLAIN are effectively tied in this sample; XOR_NEG has a marginally lower mean conflict fraction, while XOR_PLAIN has a marginally lower E-lite load skew. Keep Claude's XOR_NEG as the frozen default for interface compatibility, not because this re-screen proves a meaningful advantage over XOR_PLAIN.

## Consecutive-only E-lite replay

The reference holds one open record and merges only consecutive events with the same frame, native `(word,slot)` group, bank, and tile-word address. Different cells and ON/OFF polarity can share the record; polarity remains separate delta payload. A group, bank, tile word, or frame change flushes the record. No arbitrary within-group reordering/set merge is performed.

| Recording | Pose | Events | D2 RMW | Consecutive E-lite RMW | Reduction |
|---|---|---:|---:|---:|---:|
| sept15_yaw | POSE-0 | 1,356,547 | 1,356,547 | 781,499 | 42.39% |
| sept15_yaw | POSE-ROLL | 1,356,547 | 1,356,547 | 783,889 | 42.21% |
| sept22a_1642_32 | POSE-0 | 1,196,043 | 1,196,043 | 721,671 | 39.66% |
| sept22a_1642_32 | POSE-ROLL | 1,196,043 | 1,196,043 | 723,394 | 39.52% |
| sept22b_1642_44 | POSE-0 | 1,430,955 | 1,430,955 | 828,960 | 42.07% |
| sept22b_1642_44 | POSE-ROLL | 1,430,955 | 1,430,955 | 831,869 | 41.87% |

This is a software RMW-count comparison, not a memory timing, area, or power measurement. It measures the consecutive-only hardware semantics and therefore is lower than the earlier optimistic any-order/group merge estimate.

## Numerical effect of native-word interpolation reuse

Only the two horizontal interpolation results (`top` and `bottom`, each a 3-component Q1.15 ray vector) and their node fetches are shared. The vertical interpolation remains per event, as do ray-to-angle, binning, and address generation. Existing Exp05 fixed-point `FixedT32Mapper.map_native_group` compares the output Q1.15 rays from shared versus independent interpolation and passes bit-exactly for directed native groups. The deterministic Exp04 trace cross-check reports zero world-address mismatches on the sampled shared-mapping events. Thus reuse changes work/fetch count, not the mapped ray or world-address result. The new BAM32 address function is a pure function of that per-event Q1.15 ray, so it does not add any cross-event reuse or numerical deviation.
