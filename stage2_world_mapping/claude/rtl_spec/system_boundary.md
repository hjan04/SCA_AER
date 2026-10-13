# System Boundary: RTL V1

Status: specification, no RTL. Numeric widths marked `WAITING_FOR_CODEX_EXP05` come from Codex's fixed-point work and are not decided here.

## Evidence this boundary rests on

| Fact | Source |
|---|---|
| Sensor output is frame-scanned Group-AER: column words + 8-pixel group masks, two groups per 32-bit word, one timestamp per 773 µs frame | Exp03 (decoded real data), `FORMAT_NOTES.md` |
| 3.28–3.45 events per native word; 47–55 M ev/s mean; peak frame 125.8 k events | Exp03 |
| No pose or intrinsics in the data; pose must be supplied externally | Exp03 §0, Exp04 |
| Mapper = Warp-Grid T32 on 3-D ray nodes, 31×24 nodes, nested lerp, RNE | Codex Exp02/Exp05 draft |
| Ray → world-address (atan2) contract not yet defined; assigned to the RTL spec | Codex Exp05 `fixed_point_spec.md` |
| 2 lanes needed at 100 MHz; E-lite merge within native groups; 4 XOR banks; FIFO 128 (unproven) | Codex Exp04 freeze |

## Inside RTL V1 (synthesized logic)

| Function | Module(s) |
|---|---|
| Native-word input interface (valid/ready), coordinate validity check | `wm_input_fifo`, `wm_word_unpacker` |
| Frame-id tracking, grid-buffer selection, grid release | `wm_frame_ctrl` |
| Grid-node storage (two buffers) with a node load port and atomic commit | `wm_grid_store` |
| Event dispatch to 2 lanes (lock-step bundles) | `wm_word_unpacker` |
| Horizontal-vector reuse (native-word reuse, generalised) | `wm_hcache` + `wm_hlerp` |
| Two mapper lanes: horizontal/vertical lerp, ray→angle, world quantization | `wm_mapper_lane[2]` |
| World address generation: cell / tile word / bank / offset | `wm_addr_gen[2]` |
| E-lite within-group merge | `wm_elite_merger` |
| 4-bank routing with small per-bank queues | `wm_bank_router` |
| Per-bank read-modify-write with RAW bypass, saturating accumulate, init sweep | `wm_bank_ctrl[4]` |
| Verification/report counters | `wm_status` |

## Outside RTL V1

| Function | Where it lives | Why |
|---|---|---|
| `.dvs` file decoding | Software (`exp03_tools/dvs_decode.py`) → testbench | File I/O is not hardware. A *sensor adapter* (raw 32-bit word → core transaction) is a thin optional RTL block for later (§ adapter note) |
| Pose estimation / SLAM / optical flow / 3-D reconstruction | Not in the project scope | Organizer framing is rotation-only mapping. Pose is "externally supplied" (freeze) |
| **Grid-node generation from pose** (rotation of 744 node rays) | Software / testbench in V1; optional low-rate RTL generator later | Codex Exp05: "grid generation is a separate low-rate block or upstream software process". The V1 core exposes a node *load* port |
| World memory macros | Behavioural model `wm_mem_model` (simulation only) | No SRAM compiler in the educational 45 nm flow (Q15). Memory cost is estimated separately and reported separately |
| Map readout / visualisation | Testbench back-door read of `wm_mem_model` | Not part of the update datapath |
| Timestamps | Testbench / adapter associates frame_id ↔ time | The datapath needs only the frame id. The pose is already bound to that frame by the time it reaches the grid |

### Optional thin sensor adapter (not V1)

It converts the raw DELTA stream (`COLUMN` word sets x; `EVENT` word gives g, off, two masks, two polarities; `FRAME_END` increments frame_id) into the core transaction of `module_interfaces.md` §1. It is ~3 registers plus field extraction. Keeping it separate means the core is independent of the vendor packing and can also be driven by a single-event (XYPT) source.

## Boundary assumptions to state in the report

1. Clock target ~100 MHz (Stage 1 GPDK045 evidence: 103–107 MHz pre-layout for small designs). Not yet synthesized for Stage 2.
2. World memory is modelled as 4 independent banks, each with 1 read + 1 write port and parameterised read latency `RD_LAT`. It is **not synthesized**.
3. The grid store **is synthesized** (registers / register-file abstraction). It is a real area item: 2 × 35,712 bits at the Exp05 draft format.
4. Pose is provided per frame and is bound to a frame id before node loading.
