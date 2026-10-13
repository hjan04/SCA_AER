# Repository audit for Stage 2 implementation

Audit snapshot: branch `stage2/codex-modeling`, based on commit
`5d271a4` (`stage5-genus-ppa`). This is a read-only inventory of material
outside this Codex workspace.

## Existing organization

- RTL: `rtl/common/`, `rtl/baseline/`, `rtl/adaptive/`, plus
  `rtl/aer_tx_baseline.sv` and `rtl/aer_tx_hybrid.sv`.
- Testbenches: `tb/`, with reusable scoreboard/metrics/sink code under
  `tb/common/`, directed cases under `tb/tests/`, and the trace driver under
  `tb/traffic/`.
- Python scripts: `scripts/sweep_baseline_traffic.py`,
  `scripts/sweep_adaptive_stage3.py`, `scripts/sweep_stage4.py`, and summary
  scripts. These create traffic traces, run/aggregate RTL benchmarks, and
  generate plots. No Stage 1 Python pixel-to-world model was found.
- Simulation runners: `scripts/run_*_sim.sh` and benchmark scripts use Icarus
  Verilog (`iverilog`/`vvp`). Results include compact tracked CSV summaries and
  plots, while generated traces, per-run data, waveforms, and simulator outputs
  are kept under `traces/generated/` and `results/` according to `.gitignore`.
- Synthesis: `scripts/genus_*.tcl`; setup requirements and uncertainty are
  documented in `docs/genus_environment.md`. The Tcl references a GPDK045
  `gsclib045_svt_v4.7` library path under `/tools/config/GPDK/`, but the
  environment document says local Genus and the official competition PDK were
  not confirmed. Do not treat that path as proof the tools/library are
  available in this checkout.
- 45 nm configuration: the tracked Tcl scripts point to the named GPDK045
  library and LEFs. The documented local `gscl45nm` Qflow files are explicitly
  generic and not confirmed as the competition Cadence PDK.
- Existing results/evidence include baseline/adaptive Stage 2/3 traffic
  summaries, Stage 4 physical-link summaries and plots, and baseline/adaptive
  Genus report directories. Detailed paths are listed in
  `../shared/repository_map.md` on the common workspace when present.

## Existing DVS data and parsers

No `.aedat`, `.aedat4`, HDF5, bag, or raw event `.dat` files were found in the
repository or the local competition preparation folders inspected. No parser
for those formats was found among tracked files. `traces/generated/` contains
synthetic Stage 1 traffic traces, not real camera recordings. The local
`2차-preparations/` folder contains planning/Q&A material and screen recordings,
not a discoverable event-camera dataset. Usability for event-level evaluation:
not established; no event data or pose metadata was found.

## Stage 1 adaptive/Model2 interface evidence

This checkout contains two related interface generations, so the exact
competition-selected Model2 version should be confirmed before integration:

- The documented v0.2 hybrid transmitter is
  `rtl/aer_tx_hybrid.sv`. Input is `event_i[N_SOURCES-1:0]`, one bit per source.
  Sparse output carries a source address; dense output carries a group index and
  source mask, with `source_index = group * GROUP_SIZE + mask_bit_index`, under
  a request/acknowledge handshake. It has no timestamp, camera pose, or
  polarity output.
- The implemented sparse/dense adaptive top is
  `rtl/adaptive/aer_adaptive_top.sv` (specified in
  `docs/adaptive_aer_spec.md`). Inputs are per-pixel valid and polarity bitmaps.
  A sparse logical packet encodes pixel x, y, and polarity; a dense packet
  encodes block x/y plus valid and polarity masks. It uses `aer_req_o` /
  `aer_ack_i`. The default geometry is 16x16 pixels with 4x4 blocks.
- Stage 4's `rtl/adaptive/aer_adaptive_link_top.sv` adds a fixed-width
  valid/ready transport and preserves packet framing; it does not add camera
  pose or timestamps.

These are logical pixel/source-event interfaces, not pose-aware mapping
interfaces. The sparse/dense adaptive top carries polarity but no timestamp or
yaw/pitch/roll. A downstream adapter can consume reconstructed `(x,y,
polarity)` only after choosing the intended top/transport generation; known
pose and event timestamps need a separate agreed path. Model2 packets do not
encode precise 3D pose.
