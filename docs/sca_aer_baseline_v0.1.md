# SCA AER Baseline v0.1

Status: legacy experimental note. The approved Stage 1 conventional baseline is
documented in `baseline_spec.md` and implemented under `rtl/baseline/`.

This document defines the first local baseline for PPA comparison.

The first proposed improvement target is the traffic-adaptive hybrid AER
architecture described in `traffic_adaptive_hybrid_aer_v0.2.md`.

## Scope

The baseline is a synchronous, transmit-only AER block using a flat
fixed-priority arbiter. It is intentionally conventional and simple so that
later improvements can be compared against a defensible reference design.

## Block Diagram

```text
event_i[N-1:0]
  -> pending register
  -> flat fixed-priority arbiter
  -> address latch
  -> 4-phase req/ack FSM
  -> aer_req_o, aer_addr_o
```

## Interface

```systemverilog
module aer_tx_baseline #(
    parameter int N_SOURCES = 64,
    parameter int ADDR_W    = (N_SOURCES <= 1) ? 1 : $clog2(N_SOURCES)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic [N_SOURCES-1:0] event_i,

    output logic                 aer_req_o,
    input  logic                 aer_ack_i,
    output logic [ADDR_W-1:0]    aer_addr_o,

    output logic                 busy_o,
    output logic [N_SOURCES-1:0] pending_o
);
```

## Arbitration

The baseline uses fixed priority. Lower source index means higher priority.

```text
source 0 > source 1 > source 2 > ... > source N-1
```

Only one source can be transmitted at a time. If multiple pending bits are set,
the lowest asserted index is selected.

## Pending Policy

Each source has a single pending bit.

```text
event_i[i] == 1 -> pending[i] set
accepted event  -> pending[i] clear
```

Repeated events from a source that is already pending are merged. The baseline
does not count repeated events per source.

When a pending clear and a new event for the same source occur in the same
clock cycle, the new event is preserved:

```text
next_pending = (pending & ~clear_mask) | event_i
```

## Handshake

The output protocol is a synchronous 4-phase return-to-zero handshake.

```text
1. Transmitter drives aer_addr_o and asserts aer_req_o.
2. Receiver accepts the address and asserts aer_ack_i.
3. Transmitter deasserts aer_req_o.
4. Receiver deasserts aer_ack_i.
```

Rules:

- `aer_addr_o` is stable while `aer_req_o` is high.
- `aer_req_o` remains high until `aer_ack_i` is sampled high.
- A new transfer starts only when the transmitter is idle and `aer_ack_i` is low.
- `aer_ack_i` is assumed synchronous to `clk` for v0.1.

## Intentional Baseline Limitations

- Fixed priority can starve low-priority sources.
- Flat arbitration scales poorly as `N_SOURCES` grows.
- Backpressure on `aer_ack_i` stalls the whole transmitter.
- There is no event FIFO.
- There is no per-source event counter.
- There is no CDC or asynchronous receiver support.

## PPA Comparison Use

Recommended comparison points:

- `N_SOURCES`: 16, 32, 64, 128
- Traffic: sparse, burst, high-priority-heavy, low-priority-heavy
- Backpressure: no delay, fixed delay, random delay
- Metrics: area, power, Fmax, average latency, max latency, fairness
