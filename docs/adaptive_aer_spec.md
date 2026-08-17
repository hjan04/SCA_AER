# Traffic-Adaptive Sparse/Dense Block Bitmap AER Specification

## Motivation

Stage 2 baseline replay showed a high-load service ceiling of about 0.333
events/cycle. The dominant mechanism was the synchronous four-phase output path
servicing exactly one event per transaction. Spatial locality and delayed output
service increased one-event-per-pixel capture loss because pending pixels stayed
occupied longer.

The Stage 3 adaptive AER keeps the same event capture capacity as the baseline
and changes only how pending events are represented and serviced.

## Implemented Architecture

```text
Pixel Event Array
        |
        v
Event Capture
        |
        v
Pending Bitmap + Polarity Bitmap
        |
        +-------------------------+
        |                         |
        v                         v
Sparse Row/Column Arbiter   Block Occupancy Logic
        |                         |
        |                         v
        |                  Dense Block Selector
        |                         |
        +-----------+-------------+
                    |
                    v
              Mode Controller
                    |
        +-----------+------------+
        |                        |
        v                        v
Sparse Packetizer         Dense Packetizer
        |                        |
        +-----------+------------+
                    |
                    v
          Packet Register / REQ-ACK FSM
```

The implemented top-level RTL is `rtl/adaptive/aer_adaptive_top.sv`.

## Capture Semantics

The adaptive design instantiates the same `aer_event_capture` module used by the
baseline:

```text
one pending bit per pixel
one pending polarity bit per pixel
```

If a pixel already has a pending event and another event arrives before service,
the new event is not separately stored. This is intentional and matches the
baseline comparison model.

If an accepted sparse or dense packet clears pixel `P` on the same clock edge
that a new event arrives at `P`, the old event is transmitted and the new event
remains pending.

## Default Parameters

```text
X_SIZE = 16
Y_SIZE = 16
BLOCK_W = 4
BLOCK_H = 4
BLOCK_PIXELS = 16
DENSE_ENTER_THRESHOLD = 5
```

The RTL is parameterized for other sizes, with the main Stage 3 verification
focused on 4x4 blocks.

## Logical Packet Format

The adaptive output bus is a logical packet bus wide enough for the largest
packet:

```systemverilog
SPARSE_PACKET_W = 1 + X_W + Y_W + 1
DENSE_PACKET_W  = 1 + BLOCK_X_W + BLOCK_Y_W + BLOCK_PIXELS + BLOCK_PIXELS
PACKET_W        = max(SPARSE_PACKET_W, DENSE_PACKET_W)
```

Bit 0 is always the packet type:

```text
0 = sparse address event
1 = dense block bitmap event
```

For the default 16x16 array and 4x4 blocks:

```text
SPARSE_PACKET_W = 10 logical bits
DENSE_PACKET_W  = 37 logical bits
PACKET_W        = 37 bits
```

### Sparse Packet

General layout:

```text
bit 0                         type = 0
bits [1 +: X_W]               x
bits [1 + X_W +: Y_W]         y
bit  [1 + X_W + Y_W]          polarity
upper unused bits             zero
```

Default 16x16 layout:

```text
bit 0      type = 0
bits 4:1   x[3:0]
bits 8:5   y[3:0]
bit 9      polarity
bits 36:10 zero
```

### Dense Block Packet

General layout:

```text
bit 0                                     type = 1
bits [1 +: BLOCK_X_W]                    block_x
bits [1 + BLOCK_X_W +: BLOCK_Y_W]        block_y
next BLOCK_PIXELS bits                   valid_mask
next BLOCK_PIXELS bits                   polarity_mask
```

Default 16x16 / 4x4 layout:

```text
bit 0      type = 1
bits 2:1   block_x[1:0]
bits 4:3   block_y[1:0]
bits 20:5  valid_mask[15:0]
bits 36:21 polarity_mask[15:0]
```

Mask bit mapping is deterministic:

```text
local_index = local_y * BLOCK_W + local_x
```

Therefore:

```text
x = block_x * BLOCK_W + local_x
y = block_y * BLOCK_H + local_y
polarity = polarity_mask[local_index]
```

Only bits corresponding to valid in-array pixels are set for partial edge
blocks.

## Mode Selection

Each block occupancy is the popcount of pending pixels in that block.

```text
dense_eligible = occupancy >= DENSE_ENTER_THRESHOLD
```

The initial policy is:

```text
if any dense-eligible block exists:
    send a dense block packet
else:
    send one sparse packet
```

This is intentionally simple and can be replaced later without changing capture
semantics.

## Arbitration and Fairness

Sparse mode reuses the baseline row/column round-robin arbiter. Sparse row and
column priority advance only after a sparse packet is accepted.

Dense mode uses a round-robin arbiter over dense-eligible blocks. Dense block
priority advances only after a dense packet is accepted.

Dense packets have priority over sparse packets while at least one block is
dense-eligible. This can delay isolated sparse events under sustained dense
traffic, but it does not permanently starve dense-eligible blocks.

## Snapshot and Clear Semantics

When the output FSM starts a transaction, it latches:

```text
packet payload
clear mask
```

For dense packets, `valid_mask` and `polarity_mask` are an atomic snapshot of the
selected pending block. On successful ACK, the DUT clears exactly the latched
snapshot mask, not the current block contents.

Events arriving after snapshot formation are not included in the in-flight
packet and are not cleared by it unless they are the same-cycle clear/new case,
where the capture module intentionally clears old and captures new.

## Known Limitations

The Stage 3 packet bus is a logical bus, not a normalized physical link.
Baseline sparse packets are 9 payload bits, adaptive sparse packets are 10
logical bits because they include an explicit type bit, and adaptive dense
packets are 37 logical bits for the default configuration.

One dense logical packet handshake is not equivalent to one fixed-width physical
transfer. Stage 4 must add a common serializer or fixed-width link model before
making final throughput claims.

The block occupancy logic is fully combinational across all blocks. This is
straightforward for a student ASIC RTL prototype, but for larger arrays it may
need hierarchy or pipelining for timing closure.
