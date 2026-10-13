# Proposed Genus Synthesis Plan

Stage: 5B planning, based on Stage 5A environment discovery

## Current Status

Stage 5A found the Stage 4 RTL and regressions intact in the local WSL2
checkout, but Cadence Genus is not available on `PATH` there. Therefore this
plan defines the intended methodology and the environment prerequisites. It
does not contain final synthesis results.

## Environment Prerequisite

Before Stage 5B can begin, source the official Cadence/PDK setup provided by
the competition or server administrator.

Current reproducible state:

```text
genus executable: not found
module command: not found
Cadence setup command: unknown
```

After obtaining setup, rerun:

```bash
which genus
command -v genus
genus -version
```

Then repeat library discovery and Genus read/elaboration before final
synthesis.

## Candidate Library and Corner

Only one 45 nm candidate library was found in the local WSL2 shell:

```text
Library: gscl45nm
Liberty: /usr/local/share/qflow/tech/gscl45nm/gscl45nm.lib
Corner: typical, process 1, 1.1 V, 27 C
LEF: /usr/local/share/qflow/tech/gscl45nm/gscl45nm.lef
```

This library is not confirmed as the competition Cadence 45 nm PDK.
It remains classified only as a generic local fallback.

Stage 5B recommendation:

```text
Use the official competition 45 nm Liberty/LEF/QRC files if they become
available through the Cadence setup. Use gscl45nm typical only if the
competition explicitly accepts that library as the synthesis target.
```

If `gscl45nm` is the approved target, use `typical` for the initial fair
comparison because it is the only discovered PVT corner.

## Designs to Synthesize

### Reference: Legacy Baseline

Top:

```text
aer_baseline_top
```

Purpose:

```text
Historical Stage 1/2 reference with the original four-phase output interface.
It is not the primary fair Stage 5 comparison.
```

### Primary Fair Baseline: Baseline-Link

Top:

```text
aer_baseline_link_top
```

Purpose:

```text
Transport-normalized baseline AER using the common fixed-width physical-link
serializer.
```

### Primary Fair Adaptive: Adaptive-Link

Top:

```text
aer_adaptive_link_top
```

Purpose:

```text
Transport-normalized adaptive sparse/dense block-bitmap AER using the same
common fixed-width physical-link serializer.
```

## RTL Source Dependencies

### `aer_baseline_top`

```text
rtl/common/aer_event_capture.sv
rtl/common/aer_output_handshake.sv
rtl/common/rr_arbiter.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/baseline/aer_baseline_packetizer.sv
rtl/baseline/aer_baseline_top.sv
```

### `aer_baseline_link_top`

```text
rtl/common/aer_event_capture.sv
rtl/common/rr_arbiter.sv
rtl/common/aer_link_serializer.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/baseline/aer_baseline_packetizer.sv
rtl/baseline/aer_baseline_link_top.sv
```

### `aer_adaptive_link_top`

```text
rtl/common/aer_event_capture.sv
rtl/common/rr_arbiter.sv
rtl/common/aer_link_serializer.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/adaptive/aer_sparse_packetizer.sv
rtl/adaptive/aer_dense_packetizer.sv
rtl/adaptive/aer_block_occupancy.sv
rtl/adaptive/aer_dense_block_selector.sv
rtl/adaptive/aer_mode_controller.sv
rtl/adaptive/aer_adaptive_link_top.sv
```

## Common Parameters

Use the verified Stage 4 comparison defaults unless a separate parameter sweep
is explicitly planned:

```text
X_SIZE = 16
Y_SIZE = 16
LINK_WIDTH = 16
BLOCK_W = 4
BLOCK_H = 4
DENSE_ENTER_THRESHOLD = 5
```

For a fair primary comparison, apply the same `X_SIZE`, `Y_SIZE`, and
`LINK_WIDTH` to baseline-link and adaptive-link.

## Clock and Reset Methodology

All tops use:

```text
Clock: clk
Reset: rst_n, active-low asynchronous
```

Stage 5B should use one shared clock constraint for all three designs.

Recommended flow:

```text
1. Choose one conservative initial clock period for clean compile.
2. Run identical synthesis effort for each design.
3. Generate timing reports.
4. Tighten clock in a controlled binary-search or sweep flow to estimate Fmax.
5. Use the same sweep settings and stopping criteria for every design.
```

Do not pipeline or retime only one architecture in the first apples-to-apples
comparison.

## Common I/O Assumptions

Apply identical I/O constraints to baseline-link and adaptive-link.

Initial assumptions to define in Stage 5B:

```text
Input delay: same fraction of clock period on all primary inputs except clk/rst_n
Output delay: same fraction of clock period on all primary outputs
Output load: same load model on corresponding outputs
Input transition: same transition assumption on comparable inputs
Clock uncertainty: same value for all designs
```

Legacy baseline may use a comparable constraint set, but it remains a reference
because its output protocol is not the normalized physical link.

## Suggested Genus Flow

Once Genus and the official library are available, Stage 5B should create a
scripted flow that performs:

```text
1. Set library and search paths.
2. Read SystemVerilog RTL for exactly one top.
3. Elaborate the selected top.
4. Apply common parameters.
5. Read or create common SDC constraints.
6. Check design.
7. Run synthesis with identical effort settings.
8. Write reports.
9. Write synthesized netlist and constraints for reproducibility.
```

Reports to produce per design:

```text
report_area
report_gates or equivalent cell count report
report_timing
report_power
check_design
QoR summary
warnings/errors log
```

Do not interpret an unconstrained elaboration as meaningful PPA.

## Power Methodology

Preferred methodology:

```text
Use activity from identical Stage 4 traffic simulations for baseline-link and
adaptive-link, then feed the same style of SAIF or VCD activity into Genus.
```

Rules:

```text
Use the same trace class, seed, link-ready policy, and clock frequency.
Use the same simulation window definition.
Use the same activity conversion method.
Report vectorless power separately if it is used as a fallback.
```

Power metrics to collect:

```text
Internal dynamic power
Switching dynamic power
Leakage power
Total power
```

## Result Directory Structure

Recommended Stage 5B directories:

```text
scripts/genus/
  common_setup.tcl
  synth_legacy_baseline.tcl
  synth_baseline_link.tcl
  synth_adaptive_link.tcl

constraints/
  aer_common.sdc

results/genus/
  legacy_baseline/
  baseline_link/
  adaptive_link/

results/csv/
  stage5_ppa_summary.csv

docs/
  stage5_ppa_analysis.md
```

If the competition provides a prescribed directory or invocation style, prefer
that over this draft structure.

## Fairness Rules

The primary comparison is:

```text
Baseline-Link vs Adaptive-Link
```

Use identical:

```text
PDK
standard-cell Liberty
PVT corner
clock constraint
I/O assumptions
wire/load assumptions
synthesis effort
power activity methodology
top-level parameters
```

Do not:

```text
Pipeline only adaptive
Retiming only adaptive
Use special cells only for adaptive
Change adaptive threshold during the first PPA comparison
Give either design extra buffers or hidden storage
Use different activity traces
Use different output-link widths
```

## Metrics to Extract

Raw synthesis metrics:

```text
Total cell area
Combinational area
Sequential area
Cell count
Critical path
Worst slack
Achieved or estimated Fmax
Dynamic power
Leakage power
Total power
```

Derived metrics after real synthesis results exist:

```text
Throughput per area
Throughput per total power
Area cost per throughput improvement
Power cost per throughput improvement
```

Use the measured Stage 4 equal-physical-bandwidth throughput values for
derived metrics. Do not calculate these ratios from speculative synthesis
numbers.

## Stage 5B Entry Criteria

Before final synthesis scripts are written and trusted:

```text
Cadence Genus launches successfully.
The official 45 nm PDK/library paths are known.
The Liberty corner for the initial comparison is selected.
Genus can read and elaborate all three Stage 5 tops.
The common SDC assumptions are reviewed.
```
