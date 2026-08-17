# Traffic-Adaptive Hybrid AER Architecture v0.2

This document defines the proposed architecture that will be compared against
the synchronous flat-arbiter baseline in `sca_aer_baseline_v0.1.md`.

## Problem

Traditional address-event representation (AER) degrades under burst or
high-density event traffic because each event consumes a full arbitration and
address-transfer cycle. When many sources fire together, throughput is limited
by:

- one-at-a-time arbitration,
- per-event address transmission overhead,
- global backpressure on the transmitter,
- long flat-arbiter critical paths as source count grows,
- unfair service when fixed priority is used.

The baseline is intentionally conventional, so these limitations are expected
and measurable.

## Proposed Direction

Use a traffic-adaptive hybrid transmitter with two packetization modes:

- Sparse mode: transmit individual source addresses, optimized for low event
  density and compatibility with conventional AER behavior.
- Dense mode: transmit a compact group bitmap, amortizing one handshake over
  multiple pending events when traffic is bursty or spatially dense.

The transmitter selects the mode dynamically from current backlog and recent
traffic density. Sparse traffic avoids bitmap overhead; dense bursts avoid
paying one address transfer per source.

## Design Goals

- Preserve the baseline pending-bit semantics for a fair first comparison.
- Improve burst throughput by transmitting multiple events per handshake.
- Replace fixed-priority starvation with round-robin source or group service.
- Keep the mode switch deterministic and locally observable.
- Maintain a synchronous request/acknowledge protocol for v0.2.
- Expose enough state for latency, fairness, throughput, and PPA measurement.

## Non-Goals For v0.2

- Per-source event counters.
- Lossless repeated-event counting while a source is already pending.
- Asynchronous CDC support.
- Receiver-side event reconstruction RTL.
- Compression beyond fixed-size group bitmaps.

## Block Diagram

```text
event_i[N-1:0]
  -> pending register
  -> traffic monitor
       - pending population count
       - recent event density
       - hysteresis counters
  -> adaptive mode controller
       -> sparse path: round-robin source arbiter
       -> dense path: round-robin group scanner + group bitmap latch
  -> hybrid packet latch
  -> synchronous req/ack FSM
  -> hyb_req_o, hyb_mode_o, hyb_addr_o, hyb_group_o, hyb_mask_o
```

## Packet Interface

The baseline output only carries an address. Hybrid AER needs an explicit mode
and a bitmap payload so the receiver can distinguish single-address transfers
from grouped transfers.

```systemverilog
module aer_tx_hybrid #(
    parameter int N_SOURCES       = 64,
    parameter int GROUP_SIZE      = 8,
    parameter int ADDR_W          = (N_SOURCES <= 1) ? 1 : $clog2(N_SOURCES),
    parameter int GROUP_COUNT     = (N_SOURCES + GROUP_SIZE - 1) / GROUP_SIZE,
    parameter int GROUP_W         = (GROUP_COUNT <= 1) ? 1 : $clog2(GROUP_COUNT),
    parameter int DENSE_THRESHOLD = GROUP_SIZE,
    parameter int GROUP_DENSE_THRESHOLD = (GROUP_SIZE <= 1) ? 1 : 2,
    parameter int SPARSE_THRESHOLD = GROUP_SIZE / 2,
    parameter int MODE_EXIT_HOLD = 2
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [N_SOURCES-1:0]    event_i,

    output logic                    hyb_req_o,
    input  logic                    hyb_ack_i,
    output logic                    hyb_mode_o,
    output logic [ADDR_W-1:0]       hyb_addr_o,
    output logic [GROUP_W-1:0]      hyb_group_o,
    output logic [GROUP_SIZE-1:0]   hyb_mask_o,

    output logic                    dense_mode_o,
    output logic                    busy_o,
    output logic [N_SOURCES-1:0]    pending_o
);
```

Packet meaning:

```text
hyb_mode_o == 0:
  sparse address packet
  valid payload: hyb_addr_o

hyb_mode_o == 1:
  dense group bitmap packet
  valid payload: hyb_group_o, hyb_mask_o
  source index = hyb_group_o * GROUP_SIZE + bit_index(hyb_mask_o)
```

For `N_SOURCES` that is not an exact multiple of `GROUP_SIZE`, invalid mask
bits in the last group must be transmitted as zero.

## Pending Policy

v0.2 preserves the baseline pending-bit policy:

```text
event_i[i] == 1 -> pending[i] set
accepted packet -> included pending bit(s) clear
```

Repeated events from a source that is already pending are merged. If a pending
clear and a new event for the same source occur in the same cycle, the new event
is preserved:

```text
next_pending = (pending & ~clear_mask) | event_i
```

Dense packets clear every valid pending bit included in `hyb_mask_o`. Sparse
packets clear only the selected source.

## Mode Selection

The mode controller uses hysteresis so the transmitter does not oscillate
between sparse and dense packetization on every cycle.

Recommended first policy:

```text
enter dense mode when:
  pending_count >= DENSE_THRESHOLD
  OR max_group_pending_count >= GROUP_DENSE_THRESHOLD

leave dense mode when:
  pending_count <= SPARSE_THRESHOLD
  for MODE_EXIT_HOLD consecutive eligible cycles
```

Default parameters:

```text
GROUP_SIZE             = 8
DENSE_THRESHOLD        = 8
GROUP_DENSE_THRESHOLD  = 2
SPARSE_THRESHOLD       = 4
MODE_EXIT_HOLD         = 2
```

Dense mode does not require all transfers to be bitmap packets. If the selected
group has only one pending event, the transmitter may send a sparse packet to
avoid inefficient bitmap payloads. This keeps the mode adaptive at the packet
level as well as at the controller level.

## Arbitration

Sparse path:

- Use a round-robin source pointer.
- Select the first pending source at or after the pointer, wrapping at
  `N_SOURCES`.
- Advance the pointer after the selected packet is accepted.

Dense path:

- Divide sources into fixed groups of `GROUP_SIZE`.
- Use a round-robin group pointer.
- Select the first group with pending events at or after the pointer.
- Transmit one bitmap packet for that group when its pending population is at
  least `GROUP_DENSE_THRESHOLD`.
- Advance the group pointer after the selected packet is accepted.

This bounds service skew and removes the baseline's low-index priority bias.

## Throughput Model

Let `H` be the number of request/acknowledge handshakes and `E` be the number of
delivered source events.

Baseline:

```text
H_baseline = E
```

Hybrid sparse traffic:

```text
H_hybrid ~= E
```

Hybrid dense traffic with full groups:

```text
H_hybrid ~= ceil(E / GROUP_SIZE)
```

For `N_SOURCES = 64` and `GROUP_SIZE = 8`, a full-array burst requires up to
64 baseline handshakes but only 8 dense bitmap handshakes.

## Expected Tradeoffs

Advantages:

- Higher burst throughput.
- Lower average latency under high-density traffic.
- Lower arbitration critical-path pressure through grouped selection.
- Better fairness from round-robin service.

Costs:

- Wider output payload in dense mode.
- Additional popcount, group-scan, and mode-control logic.
- Receiver must understand hybrid packets.
- Sparse-only traffic may see slightly higher area and control overhead than
  the baseline.

## Verification Plan

Directed tests:

- single sparse event,
- multiple sparse events across wrap boundary,
- dense full-group burst,
- dense partial last group,
- transition from sparse to dense and back,
- clear/set same-cycle preservation for sparse and dense packets,
- backpressure stability for both packet modes,
- round-robin fairness with persistent mixed traffic.

Random tests:

- random event masks with configurable density,
- random acknowledge delay,
- scoreboard that reconstructs delivered source events from sparse and dense
  packets,
- latency histogram per source,
- fairness spread between most-served and least-served active sources.

Comparison metrics:

- handshakes per delivered event,
- average and maximum latency,
- sustained output events per cycle,
- source fairness,
- synthesized area,
- estimated dynamic power,
- Fmax.

## Implementation Milestones

1. Add a cycle-level hybrid transmitter RTL model.
2. Add a self-checking hybrid testbench with sparse, dense, and mixed traffic.
3. Add a common traffic generator so baseline and hybrid see identical stimuli.
4. Add scripts that report handshakes, delivered events, latency, and fairness.
5. Synthesize both transmitters at `N_SOURCES = 16, 32, 64, 128`.
