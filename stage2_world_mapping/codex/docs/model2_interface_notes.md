# Model2 interface notes for a future pixel-to-world adapter

This note describes the existing Stage 1 logical packet interface only; it does
not propose a change to Model2.

## Observed logical interfaces

The checkout contains related but distinct adaptive interfaces; the exact
competition-selected Model2 revision should be confirmed before integration.

`rtl/adaptive/aer_adaptive_top.sv`, specified by `docs/adaptive_aer_spec.md`,
has per-pixel input bitmaps `pixel_event_valid_i[N_PIXELS-1:0]` and
`pixel_event_pol_i[N_PIXELS-1:0]`. Its default parameters describe a 16x16
array. Output is `aer_packet_o[PACKET_W-1:0]` with `aer_req_o` / `aer_ack_i`.
Sparse logical packets include x, y, and polarity. Dense logical packets
include block x/y and valid/polarity masks; each mask bit maps to a pixel within
the block. The source holds at most one pending event per pixel, so repeated
events at a pending pixel merge according to the documented capture semantics.

The older documented v0.2 module `rtl/aer_tx_hybrid.sv` uses one input bit per
source and the `hyb_req_o` / `hyb_ack_i` handshake. Sparse output is a source
address; dense output is a group and mask, decoded as
`group * GROUP_SIZE + set_bit_index`. That interface does not expose polarity.

## Future adapter input

A downstream software/hardware adapter can decode the current adaptive top's
sparse/dense packets into `(x,y,polarity)` events. It must receive known camera
pose and timestamps through a separate agreed path; they cannot be recovered
from these Model2 packet fields. If the older v0.2 interface is the selected
version, its source-index-to-coordinate mapping and polarity path also need to
be agreed. Do not assume a direct wire-compatible connection to the Stage 2
event tuple `(x,y,polarity,timestamp,yaw,pitch,roll)`.

The Stage 4 normalized physical link is separately documented in
`docs/physical_link_spec.md`; it reconstructs sparse `{x,y,polarity}` events
after transport but still does not include timestamp or camera pose.
