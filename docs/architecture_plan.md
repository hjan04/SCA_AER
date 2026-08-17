# AER Architecture Plan

Stage 0 planning document for the university AI semiconductor circuit design
competition project.

This plan defines the conventional baseline, candidate adaptive architectures,
verification strategy, benchmark metrics, and implementation order. Stage 1 RTL
work should not proceed until this plan is reviewed and approved.

## Current Repository Inspection

The current workspace contains:

```text
docs/
  sca_aer_baseline_v0.1.md
  traffic_adaptive_hybrid_aer_v0.2.md
rtl/
  aer_tx_baseline.sv
  aer_tx_hybrid.sv
scripts/
  run_baseline_sim.sh
  run_hybrid_sim.sh
tb/
  tb_aer_tx_baseline.sv
  tb_aer_tx_hybrid.sv
results/
```

All listed project files are currently untracked in git. The current structure
is useful for early experiments, but the project should be reorganized before
the main baseline, benchmark, and adaptive implementations are treated as
competition deliverables.

## Proposed Project Directory Structure

```text
SCA_AER/
  README.md
  docs/
    architecture_plan.md
    baseline_spec.md
    adaptive_candidate_comparison.md
    benchmark_methodology.md
    genus_notes.md
  rtl/
    common/
      aer_pkg.sv
      rr_arbiter.sv
      sync_fifo.sv
      aer_event_capture.sv
      aer_output_handshake.sv
    baseline/
      aer_baseline_top.sv
      aer_row_col_arbiter.sv
      aer_baseline_packetizer.sv
    adaptive/
      aer_adaptive_top.sv
      aer_density_monitor.sv
      aer_mode_controller.sv
      aer_sparse_path.sv
      aer_dense_path.sv
      aer_adaptive_packetizer.sv
  tb/
    common/
      tb_aer_types_pkg.sv
      tb_scoreboard.sv
      tb_metrics.sv
      tb_output_sink.sv
    traffic/
      tb_trace_driver.sv
      tb_random_traffic_gen.sv
      tb_poisson_traffic_gen.sv
      tb_hotspot_traffic_gen.sv
      tb_burst_traffic_gen.sv
    tests/
      tb_baseline_directed.sv
      tb_benchmark_baseline.sv
      tb_benchmark_adaptive.sv
      tb_compare_baseline_adaptive.sv
  scripts/
    run_baseline_sim.sh
    run_benchmark.sh
    sweep_traffic.sh
    summarize_results.py
    run_genus_baseline.tcl
    run_genus_adaptive.tcl
  traces/
    README.md
  results/
    raw/
    csv/
    plots/
  synth/
    genus/
```

The `rtl/common` directory should contain reusable synthesizable modules that
are not biased toward either architecture. The `tb` directory may contain
non-synthesizable infrastructure. Raw traces and raw CSV results should be
preserved so comparisons can be reproduced.

## Conventional AER At The RTL Level

A DVS-like pixel array raises request bits when pixels generate events. Each
event contains:

- x coordinate,
- y coordinate,
- polarity.

At the digital RTL boundary, the pixel array is modeled as one event-valid bit
per pixel plus one polarity bit per pixel for events asserted in that cycle.
Because multiple pixels may fire simultaneously, the request input is a vector.

A conventional AER transmitter captures pending pixel requests, arbitrates among
pending pixels, encodes the selected pixel address, transmits one address-event
packet, waits for acknowledge, and then clears the selected pending request.
Only one event is transmitted per output handshake.

## Baseline Architecture

The baseline should be a fair conventional AER design, not an intentionally weak
reference. The proposed baseline is a synchronous, two-level row/column
round-robin AER transmitter.

```text
pixel_event_valid_i[Y][X], pixel_event_pol_i[Y][X]
  -> event capture and polarity latch
  -> row request reduction
  -> round-robin row arbiter
  -> round-robin column arbiter within selected row
  -> x/y/polarity packetizer
  -> optional one-entry output register
  -> synchronous request/acknowledge output interface
  -> clear accepted pixel request
```

Why two-level row/column arbitration:

- It matches the natural 2D structure of a DVS-like pixel array.
- It is still simple enough for student RTL and Cadence synthesis.
- It avoids fixed-priority starvation, which would make the baseline less fair.
- It keeps the conventional bottleneck: one event is transmitted per output
  transfer.
- It scales better than a single flat scan as array size increases.

The baseline does not use dense packets, compression, multi-event output
packets, or traffic-dependent mode changes.

## Exact Interface Proposal

Use parameterized array dimensions:

```systemverilog
parameter int X_SIZE = 16;
parameter int Y_SIZE = 16;
parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE);
parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE);
parameter int N_PIXELS = X_SIZE * Y_SIZE;
```

For Stage 1 simulation, `8x8` or `16x16` is sufficient. The RTL should remain
parameterizable for larger sweeps.

Proposed baseline top-level interface:

```systemverilog
module aer_baseline_top #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int EVENT_W = X_W + Y_W + 1
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [N_PIXELS-1:0]   pixel_event_valid_i,
    input  logic [N_PIXELS-1:0]   pixel_event_pol_i,

    output logic                  aer_req_o,
    input  logic                  aer_ack_i,
    output logic [EVENT_W-1:0]    aer_event_o,

    output logic                  busy_o,
    output logic [N_PIXELS-1:0]   pending_o
);
```

`pending_o` is primarily for verification and debug. It is synthesizable but may
be excluded from final synthesis wrappers if it is not needed.

Proposed adaptive top-level interface should preserve the same input side and
request/acknowledge style. Its output payload may be wider because adaptive
packets can contain sparse or dense packet types. The benchmark must account for
the different packet widths through `bits transmitted per event`.

## Request/ACK Timing Behavior

Use a synchronous four-phase request/acknowledge protocol for the first-stage
RTL:

```text
1. Transmitter selects a packet and drives payload.
2. Transmitter asserts req.
3. Receiver samples payload and asserts ack.
4. Transmitter samples ack high, deasserts req, and clears accepted event(s).
5. Receiver deasserts ack.
6. Transmitter may start the next transfer only when ack is low.
```

Timing rules:

- Payload must be stable while `req` is high.
- `req` remains high until `ack` is sampled high on a clock edge.
- Accepted event clear happens when `req && ack` is sampled.
- A new event arriving in the same cycle that its previous pending bit is
  cleared must be preserved as a new pending event.
- `ack` is assumed synchronous to `clk` for Stage 1 and Stage 2.

This protocol is conservative and maps cleanly to synthesizable RTL. A later
streaming `valid/ready` wrapper can be added if needed, but the benchmark should
use one common output sink policy for both DUTs.

## Event Packet Format

Baseline packet:

```text
bit [X_W-1:0] x
bit [Y_W-1:0] y
bit           polarity
```

Packed baseline payload:

```text
aer_event_o = {polarity, y, x}
EVENT_W = 1 + Y_W + X_W
```

Coordinate mapping from pixel index:

```text
pixel_index = y * X_SIZE + x
x = pixel_index % X_SIZE
y = pixel_index / X_SIZE
```

For the adaptive architecture, the output packet should include a packet type:

```text
type = SPARSE:
  {type, polarity, y, x}

type = DENSE_BLOCK:
  {type, block_y, block_x, valid_mask, polarity_mask}
```

For a dense block with `BLOCK_W * BLOCK_H` pixels:

- `valid_mask[i] = 1` means the pixel offset is included in the packet.
- `polarity_mask[i]` gives the polarity for that included pixel.
- Invalid or unused mask bits in partial edge blocks must be zero.

This dense format represents multiple events while keeping exact pixel
coordinates reconstructable by the receiver.

## Baseline Capture Policy

Each pixel has one pending bit and one pending polarity bit.

```text
new event when pending == 0:
  set pending and latch polarity

new event when pending == 1 and not clearing:
  event is merged/lost at the capture level

clear and new event for same pixel in same cycle:
  clear old event and capture new event
```

This is a reasonable conventional AER simplification. It does mean that repeated
events from the same pixel can be lost during congestion. The benchmark must
measure this as event loss rather than ignoring it.

## Expected Conventional AER Bottlenecks

- One output transaction carries only one event.
- High-density traffic creates a pending backlog faster than it can be drained.
- Repeated events from already-pending pixels are merged or lost.
- Arbitration delay grows with array size.
- Output backpressure stalls all pending event service.
- Average and maximum latency rise sharply near saturation.
- Bursts and hotspots can create localized unfairness if arbitration is not
  carefully designed.

Even with round-robin arbitration, the baseline remains limited by one event per
request/acknowledge transfer.

## Measurable Performance Metrics

Simulation metrics:

- generated events,
- transmitted events,
- lost events,
- total simulation cycles,
- handshakes,
- throughput in events/cycle,
- throughput in events/second for a chosen clock frequency,
- average latency in cycles,
- maximum latency in cycles,
- event loss rate,
- bits transmitted per event,
- output utilization,
- maximum sustainable input event rate.

Synthesis metrics:

- cell area,
- combinational area,
- sequential area,
- estimated dynamic power,
- estimated leakage power,
- timing slack,
- maximum clock frequency.

No performance number should be reported unless it comes from simulation or
synthesis.

## Adaptive Candidate 1: Sparse/Dense Block Bitmap AER

Architecture:

```text
event capture
  -> density monitor
  -> sparse path: conventional x/y/polarity event
  -> dense path: block selector + valid/polarity bitmap packet
  -> output FIFO/register
  -> request/acknowledge interface
```

Under sparse traffic, transmit conventional single-event packets. Under dense or
hotspot traffic, select a block and transmit a bitmap describing multiple
pending pixels in that block.

Pros:

- Strong throughput improvement for burst, hotspot, and simultaneous events.
- Reduces address overhead because block coordinates are shared.
- Exact event coordinates are recoverable.
- Decoder is simple: expand block coordinate plus set mask bits.
- Hardware is synthesizable using counters, masks, arbiters, and registers.
- Good fit for a student ASIC project because behavior is visible and
  measurable.

Cons:

- Wider packet than baseline.
- More control logic: density monitor, block scanner, mask extraction.
- Sparse-only traffic may have modest area and power overhead.
- Dense packets are less efficient when only one event exists in a block.
- Need careful edge-block handling when dimensions are not multiples of block
  size.

Event loss behavior:

- If capture depth remains one event per pixel, same-pixel repeated events can
  still be lost.
- Dense output reduces backlog, so loss should decrease under high-density
  traffic if output congestion is the dominant cause.

Cadence suitability:

- High. Logic is regular, synthesizable, and does not require memories or
  vendor-specific primitives.

## Adaptive Candidate 2: Multi-Event Address Packet AER

Architecture:

```text
event capture
  -> arbiter
  -> event collector packs up to K x/y/polarity events
  -> output FIFO/register
  -> request/acknowledge interface
```

Instead of changing to block bitmaps, this approach packs several conventional
address events into one output packet.

Pros:

- Simple conceptual extension of baseline AER.
- Decoder is easy because each event still has explicit x/y/polarity fields.
- Good for uniform random traffic where events are not spatially clustered.
- Reduced handshake overhead by sending up to `K` events per packet.

Cons:

- Does not reduce address bits per event much because each event still carries a
  full address.
- Requires a wider output packet or multiple output beats per packet.
- Needs collector control and possibly an output FIFO.
- If the arbiter still selects one event per cycle, packing may not remove the
  input arbitration bottleneck.

Event loss behavior:

- Can reduce loss caused by output handshake overhead.
- Does not directly improve repeated same-pixel capture loss unless capture
  buffering is also increased.

Cadence suitability:

- High. Mostly registers, muxes, counters, and FIFO logic.

## Adaptive Candidate 3: Hierarchical Banked AER With Local FIFOs

Architecture:

```text
pixel array
  -> per-bank capture
  -> local row/column arbiters
  -> small local FIFOs
  -> global scheduler
  -> output interface
```

The array is divided into banks or tiles. Each bank arbitrates locally and stores
events in a small FIFO. A global scheduler drains banks based on occupancy,
round-robin priority, or traffic density.

Pros:

- Reduces long global arbitration paths.
- Improves local burst absorption if FIFOs are deep enough.
- Maintains conventional event packets, so decoder is simple.
- Provides useful architecture knobs: bank size, FIFO depth, scheduler policy.

Cons:

- Higher area from multiple arbiters and FIFOs.
- Higher clock and switching power under high activity.
- More verification complexity because FIFO overflow must be tracked.
- Output still becomes a bottleneck if only one event is transmitted per
  handshake.
- Less direct bits/event improvement unless combined with packet packing.

Event loss behavior:

- Local FIFOs can reduce event loss during short bursts.
- FIFO overflow must be measured explicitly.

Cadence suitability:

- Medium to high. Synthesizable, but area and timing are more sensitive to FIFO
  implementation choices.

## Adaptive Candidate Comparison

```text
Criterion               Block bitmap      Multi-event packet   Banked local FIFO
Expected throughput     High for dense     Medium              Medium
Bits/event improvement  High for clusters  Low to medium       Low
Area overhead           Medium             Low to medium       Medium to high
Power overhead          Medium             Medium              Medium to high
Implementation effort   Medium             Low to medium       Medium to high
Decoder complexity      Low to medium      Low                 Low
Event loss reduction    Medium to high     Medium              Medium
Uniform traffic fit     Medium             High                Medium
Hotspot/burst fit       High               Medium              High
Cadence synthesis fit   High               High                Medium to high
```

## Recommended Adaptive Architecture

The recommended first adaptive architecture is Candidate 1: sparse/dense block
bitmap AER.

Reasons:

- It directly targets the research question: burst and high-density congestion.
- It can reduce both handshake overhead and address bits per delivered event.
- It preserves exact x/y/polarity reconstruction.
- It is implementable with straightforward synthesizable SystemVerilog.
- It has clear parameters for competition experiments: block width, block
  height, dense threshold, output FIFO depth, and mode hysteresis.
- It gives an intuitive comparison against the conventional baseline without
  making the baseline artificially weak.

Suggested first adaptive parameters:

```text
X_SIZE = 16
Y_SIZE = 16
BLOCK_W = 4
BLOCK_H = 4
BLOCK_PIXELS = 16
DENSE_ENTER_THRESHOLD = 4 pending events in a block
DENSE_EXIT_THRESHOLD = 1 or 2 pending events in selected block
OUTPUT_FIFO_DEPTH = 2 to 4 packets
```

These are starting points only. Final values should be swept in simulation.

## Benchmark Methodology

The benchmark must replay exactly the same event trace into both DUTs.

Trace representation:

```text
event_id, cycle, x, y, polarity
```

A trace driver groups all rows with the same cycle into one
`pixel_event_valid_i` vector and a matching `pixel_event_pol_i` vector.

Traffic classes:

- very sparse random events,
- uniform random events,
- Poisson-like event arrivals,
- localized hotspot events,
- short high-intensity bursts,
- simultaneous multi-pixel events,
- overload traffic beyond expected sustainable rate.

Traffic intensity sweep:

```text
low -> medium -> high -> saturation -> overload
```

Fairness requirements:

- Same `X_SIZE`, `Y_SIZE`, clock, reset duration, trace, simulation length, and
  output sink policy for both DUTs.
- Same input event timing, including simultaneous events.
- Same measurement definitions.
- Same random seed when generated traces are used.
- Raw traces are saved before simulation.
- Raw per-run CSV metrics are saved after simulation.

Output sink policy:

- Start with an always-ready sink that acknowledges every valid request using
  the defined four-phase handshake.
- Add fixed-delay and random-delay acknowledge modes later to study
  backpressure.
- Use the same sink mode for baseline and adaptive runs.

CSV result fields:

```text
architecture,
traffic_name,
seed,
x_size,
y_size,
sim_cycles,
input_rate_events_per_cycle,
generated_events,
transmitted_events,
lost_events,
handshakes,
bits_transmitted,
bits_per_event,
throughput_events_per_cycle,
average_latency_cycles,
maximum_latency_cycles,
event_loss_rate,
output_utilization,
notes
```

Latency definition:

```text
latency = output_accept_cycle - input_generation_cycle
```

For repeated events from the same pixel, the scoreboard should match each output
event to the oldest outstanding generated event with the same x/y/polarity that
can be represented by the DUT capture model. Unmatched generated events at the
end of the run count as lost.

Saturation point definition:

```text
maximum sustainable input event rate =
  highest offered input rate where throughput remains close to input rate
  and event loss rate remains below the selected threshold
```

The selected threshold should be reported explicitly, for example `1%` loss or
`0.1%` loss. Do not hide overload behavior.

## Event Loss Accounting

Event loss can occur because:

- a new event arrives for a pixel that is already pending,
- an output FIFO overflows,
- an adaptive packet buffer overflows,
- simulation ends before all pending events drain.

The benchmark should report loss categories when possible:

```text
capture_loss
fifo_overflow_loss
undrained_at_end
total_loss
```

If the RTL does not expose enough information to distinguish categories, the
scoreboard may report only total loss and state that category attribution is not
available for that run.

## RTL Modules Eventually Needed

Common synthesizable modules:

- `aer_pkg.sv`: shared parameters, typedefs, packet constants.
- `rr_arbiter.sv`: reusable round-robin arbiter.
- `sync_fifo.sv`: optional parameterized synchronous FIFO.
- `aer_event_capture.sv`: pending and polarity latch array.
- `aer_output_handshake.sv`: common request/acknowledge FSM.

Baseline modules:

- `aer_baseline_top.sv`
- `aer_row_col_arbiter.sv`
- `aer_baseline_packetizer.sv`

Adaptive modules:

- `aer_adaptive_top.sv`
- `aer_density_monitor.sv`
- `aer_mode_controller.sv`
- `aer_sparse_path.sv`
- `aer_dense_block_selector.sv`
- `aer_dense_packetizer.sv`
- `aer_adaptive_output_fifo.sv`

Verification modules:

- trace generator,
- trace replay driver,
- output sink,
- baseline packet decoder,
- adaptive packet decoder,
- scoreboard,
- metrics collector,
- CSV writer,
- directed tests,
- benchmark sweep tests.

Scripts:

- simulation compile/run scripts,
- traffic sweep script,
- CSV summarizer,
- plot generator,
- Cadence Genus synthesis scripts.

## Step-By-Step Implementation Order

1. Approve or revise this Stage 0 architecture plan.
2. Reorganize the repository into the approved directory structure.
3. Write `README.md` with project goals, assumptions, and run instructions.
4. Write `rtl/common/aer_pkg.sv` with shared parameters and packet definitions.
5. Implement common `rr_arbiter.sv`.
6. Implement baseline event capture with pending and polarity storage.
7. Implement baseline row/column round-robin arbiter.
8. Implement baseline packetizer and request/acknowledge FSM.
9. Add baseline directed self-checking testbench.
10. Verify single event, simultaneous events, continuous events, repeated
    same-pixel events, and heavy traffic for the baseline.
11. Build trace representation and replay driver.
12. Build output monitors, packet decoders, scoreboard, and metrics collector.
13. Add CSV result writing.
14. Run baseline benchmark sweeps and preserve raw results.
15. Revisit adaptive candidate choice using baseline bottleneck data.
16. Implement selected adaptive architecture only after approval.
17. Run identical traces against baseline and adaptive DUTs.
18. Produce comparison CSVs and plots.
19. Add Genus synthesis scripts for baseline.
20. Add Genus synthesis scripts for adaptive design.
21. Compare area, power, and timing with the simulation metrics.

## Stage Gate

Stage 1 should begin only after the following decisions are approved:

- baseline arbitration policy,
- baseline capture/loss policy,
- packet formats,
- benchmark traffic classes,
- CSV metric definitions,
- recommended adaptive architecture or revised candidate list.
