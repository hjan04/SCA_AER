# Conventional Baseline AER Specification

This document describes the Stage 1 conventional AER baseline RTL and directed
self-checking verification.

## Scope

The baseline is a synthesizable, synchronous, transmit-only digital AER block
for a DVS-like pixel event array. It implements conventional one-event-per-output
transaction behavior and is intended to be a fair reference for later
traffic-adaptive AER work.

The Stage 1 baseline does not implement adaptive modes, dense packets, traffic
generators, CSV benchmark output, or synthesis scripts.

## Block Diagram

```text
pixel_event_valid_i[N-1:0], pixel_event_pol_i[N-1:0]
  -> Event Capture
  -> Pending Bitmap + Polarity Storage
  -> Row Request Reduction
  -> Round-Robin Row Arbiter
  -> Round-Robin Column Arbiter
  -> Address Encoder / Packetizer
  -> Output Register
  -> Synchronous REQ/ACK Interface
```

## Module Hierarchy

```text
aer_baseline_top
  -> aer_event_capture
  -> aer_row_col_arbiter
       -> rr_arbiter for rows
       -> rr_arbiter for columns
  -> aer_baseline_packetizer
  -> aer_output_handshake
```

RTL files:

```text
rtl/common/aer_pkg.sv
rtl/common/rr_arbiter.sv
rtl/common/aer_event_capture.sv
rtl/common/aer_output_handshake.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/baseline/aer_baseline_packetizer.sv
rtl/baseline/aer_baseline_top.sv
```

## Top-Level Interface

```systemverilog
module aer_baseline_top #(
    parameter int X_SIZE = 16,
    parameter int Y_SIZE = 16,
    parameter int X_W = (X_SIZE <= 1) ? 1 : $clog2(X_SIZE),
    parameter int Y_W = (Y_SIZE <= 1) ? 1 : $clog2(Y_SIZE),
    parameter int N_PIXELS = X_SIZE * Y_SIZE,
    parameter int EVENT_W = 1 + Y_W + X_W
) (
    input  logic                clk,
    input  logic                rst_n,

    input  logic [N_PIXELS-1:0] pixel_event_valid_i,
    input  logic [N_PIXELS-1:0] pixel_event_pol_i,

    output logic                aer_req_o,
    input  logic                aer_ack_i,
    output logic [EVENT_W-1:0]  aer_event_o,

    output logic                busy_o
);
```

Pixel indexing:

```text
pixel_index = y * X_SIZE + x
```

## Packet Format

One accepted output transaction represents exactly one event.

```text
aer_event_o = {polarity, y, x}
EVENT_W = 1 + Y_W + X_W
```

For the default `16x16` configuration:

```text
X_W = 4
Y_W = 4
EVENT_W = 9
```

No timestamp, intensity value, compression field, or adaptive packet type is
included in the baseline packet.

## Request/ACK Timing

The output interface uses a synchronous four-phase handshake:

```text
IDLE
  -> select pending event
  -> drive registered payload and assert aer_req_o
  -> wait for aer_ack_i high
  -> accept selected event and clear its pending bit
  -> deassert aer_req_o
  -> wait for aer_ack_i low
  -> return to IDLE
```

Rules:

- `aer_event_o` remains stable while `aer_req_o` is high.
- `aer_req_o` remains high until `aer_ack_i` is sampled high.
- The selected event is cleared only when `aer_req_o && aer_ack_i` is sampled.
- A new request can start only after `aer_ack_i` returns low.
- `aer_ack_i` is assumed synchronous to `clk` for this stage.

## Event Capture Semantics

Each pixel has one pending bit and one pending polarity bit.

```text
pending == 0 and new event:
  set pending and latch polarity

pending == 1 and new event, without clear:
  keep the old pending event and old polarity

pending event accepted and new same-pixel event in the same cycle:
  clear old event and capture the new event
```

This one-event-per-pixel capture policy is intentional. Repeated same-pixel
events while already pending cannot be separately stored and will later be
counted as capture loss by the benchmark infrastructure.

## Arbitration Policy

The baseline uses two-level round-robin arbitration:

```text
pending bitmap
  -> OR-reduce each row
  -> row round-robin select
  -> column vector for selected row
  -> column round-robin select
```

The row and column priority bases advance only after a successful output
acceptance. They do not advance merely because an event was selected or because
`aer_req_o` was asserted.

After accepting event `(x, y)`:

```text
next row priority starts at y + 1, wrapping at Y_SIZE
next column priority starts at x + 1, wrapping at X_SIZE
```

This avoids permanent starvation while preserving the conventional
one-event-per-transfer AER bottleneck.

## Known Bottlenecks

- Only one event is transmitted per REQ/ACK transaction.
- Dense simultaneous traffic drains over many handshakes.
- Repeated events from a pixel that is already pending are merged.
- Output backpressure stalls event service.
- Latency rises as the pending bitmap fills.
- Arbitration logic grows with array dimensions.

These are expected conventional AER limits, not test failures.

## Known Loss Mechanism

The Stage 1 RTL has no loss counter. The approved capture policy means a second
event from the same pixel is not separately represented if that pixel is already
pending and not being cleared in the same cycle.

The directed testbench verifies this behavior explicitly. Full quantitative loss
accounting belongs to Stage 2.

## Directed Verification

The Stage 1 directed testbench is:

```text
tb/tests/tb_baseline_directed.sv
```

It instantiates a `4x4` baseline for fast simulation and checks:

- single event,
- multiple simultaneous events,
- round-robin fairness,
- delayed ACK and payload stability,
- back-to-back traffic,
- same-pixel repeated event while pending,
- same-cycle clear plus new same-pixel event,
- heavy simultaneous traffic.

The testbench includes a simple scoreboard that tracks expected `{x, y,
polarity}` events and detects missing, duplicate, unexpected, or incorrectly
encoded output events.

It also checks:

- payload stability while `aer_req_o` is high,
- no X/Z payload on accepted events,
- accepted coordinates are inside the configured array,
- pending is not cleared before ACK,
- same-cycle clear/new-event capture is preserved.

## Simulation Command

Run:

```bash
scripts/run_baseline_sim.sh
```

Expected result:

```text
[TEST] single_event         PASS
[TEST] simultaneous         PASS
[TEST] round_robin          PASS
[TEST] delayed_ack          PASS
[TEST] back_to_back         PASS
[TEST] repeated_pixel       PASS
[TEST] clear_and_new        PASS
[TEST] heavy_traffic        PASS

BASELINE DIRECTED TESTS: PASS
```

The script also writes a VCD waveform:

```text
results/waves/baseline_directed.vcd
```
