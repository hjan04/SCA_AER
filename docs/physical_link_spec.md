# Stage 4 Physical Link Specification

## Purpose

Stage 4 separates AER event encoding from physical transport bandwidth. The
legacy baseline and adaptive AER no longer compare one narrow sparse event
handshake against one wide dense packet handshake. Instead, both architectures
produce logical packets that pass through the same fixed-width physical link.

```text
Pixel events
    -> AER architecture
    -> logical packet
    -> common serializer
    -> fixed-width valid/ready physical link
    -> common deserializer
    -> logical packet decoder
    -> canonical {x, y, polarity} events
```

## Link Interface

The physical link is a single-clock valid/ready interface:

```systemverilog
output logic                  link_valid_o;
input  logic                  link_ready_i;
output logic [LINK_WIDTH-1:0] link_data_o;
```

A physical beat transfers on a rising clock edge when:

```text
link_valid_o && link_ready_i
```

If `link_valid_o == 1` and `link_ready_i == 0`, `link_data_o` must remain
stable. The link clock is the same clock used by the DUT in Stage 4 simulation.

The primary comparison uses:

```text
LINK_WIDTH = 16
```

The serializer/deserializer are parameterized and were also tested with:

```text
LINK_WIDTH = 8
LINK_WIDTH = 32
```

## Transport Header

Every logical packet is framed with an 8-bit transport header:

```text
bit [1:0] packet_type
bit [7:2] payload_length_bits
```

The frame is serialized least-significant bit first. The receiver reconstructs
packet type and payload length from the header. No simulator-only sideband
information is used to reconstruct packet boundaries, packet type, block
coordinates, masks, or event count.

Packet type values are:

```text
0: baseline sparse packet
1: adaptive sparse packet
2: adaptive dense block packet
3: reserved
```

## Payload Formats

For the default 16x16 array:

```text
X_W = 4
Y_W = 4
```

### Baseline Sparse Payload

Payload:

```text
{polarity, y, x}
```

Width:

```text
9 bits
```

### Adaptive Sparse Payload

Payload:

```text
{polarity, y, x, adaptive_payload_type=0}
```

Width:

```text
10 bits
```

The adaptive payload type bit is retained from the Stage 3 logical packet
format. It is not free; it is serialized over the physical link.

### Adaptive Dense Block Payload

Default geometry:

```text
BLOCK_W = 4
BLOCK_H = 4
BLOCK_PIXELS = 16
BLOCK_X_COUNT = 4
BLOCK_Y_COUNT = 4
BLOCK_X_W = 2
BLOCK_Y_W = 2
```

Payload:

```text
adaptive_payload_type
block_x
block_y
valid_mask[15:0]
polarity_mask[15:0]
```

Width:

```text
1 + 2 + 2 + 16 + 16 = 37 bits
```

Mask bit mapping:

```text
local_index = local_y * BLOCK_W + local_x
valid_mask[local_index]
polarity_mask[local_index]
```

## Padding Rules

The serializer transmits:

```text
frame_bits = header_bits + payload_bits
physical_beats = ceil(frame_bits / LINK_WIDTH)
physical_bits = physical_beats * LINK_WIDTH
```

Only the final beat may contain padding. Padding bits are zero and are not
interpreted by the receiver.

For `LINK_WIDTH = 16`:

| Packet | Payload Bits | Header + Payload | Beats | Physical Bits |
| --- | ---: | ---: | ---: | ---: |
| Baseline sparse | 9 | 17 | 2 | 32 |
| Adaptive sparse | 10 | 18 | 2 | 32 |
| Adaptive dense 4x4 | 37 | 45 | 3 | 48 |

## Physical Break-Even

Using the Stage 4 wire format:

```text
dense is cheaper when dense_physical_bits < N * sparse_physical_bits
```

For a 4x4 dense packet:

| LINK_WIDTH | Sparse Physical Cost | Dense Physical Cost | Strict Break-Even |
| ---: | ---: | ---: | ---: |
| 8 | 24 bits | 48 bits | 3 events |
| 16 | 32 bits | 48 bits | 2 events |
| 32 | 32 bits | 64 bits | 3 events |

The RTL still uses `DENSE_ENTER_THRESHOLD = 5` for the primary Stage 4 run so
that the comparison starts from the approved Stage 3 architecture. Stage 4 also
runs a threshold sweep for 3, 4, 5, 6, and 8.

## Backpressure Policies

The deserializer exposes the physical `link_ready_i` seen by the DUT. Stage 4
supports:

```text
always:   receiver is always ready
periodic: receiver stalls for STALL_CYCLES every STALL_PERIOD cycles
random:   receiver uses a fixed-seed LFSR and RANDOM_STALL_PERCENT
```

The same ready policy and seed must be used for baseline and adaptive runs.

## Buffer Fairness Audit

| Buffer | Baseline Link Top | Adaptive Link Top |
| --- | --- | --- |
| Per-pixel pending bit | one per pixel | one per pixel |
| Per-pixel polarity bit | one per pixel | one per pixel |
| Per-pixel FIFO | none | none |
| Logical packet buffer | common serializer frame register | common serializer frame register |
| Physical receiver buffer | common deserializer frame register | common deserializer frame register |
| Dense snapshot storage | none | selected block mask/polarity snapshot through packet frame |
| Additional FIFO | none | none |

The adaptive dense snapshot is architectural state and must be counted in later
area/power/timing evaluation. It is not hidden transport bandwidth.

## Measurement Definitions

Stage 4 records:

```text
physical_link_beats
physical_bits = physical_link_beats * LINK_WIDTH
physical_bits_per_delivered_event
logical_packets
sparse_packets
dense_packets
delivered_events
event_loss_rate
end_to_end_latency_cycles
```

Latency is measured from input event generation cycle to receiver-side
reconstruction of the canonical event. Dense packet events are delivered only
after the receiver has reconstructed the full dense packet from all physical
beats.
