# Adaptive Precision: Extend Stage 1's Philosophy or Reject It?

Question: can mapping precision or update policy vary with event density, in the way Stage 1 switched sparse/dense packetization?

Short answer (hypothesis, pending Experiment 03):
- **Adaptive *update granularity*: yes, worth testing.**
- **Adaptive *spatial precision*: reject, except as an explicit, measured overload policy.**

## 1. Why Stage 1 adaptivity was clean

The Stage 1 dense packet is *lossless* relative to the sparse path. It carries the same pixels and polarities (given pending-bit semantics), only encoded more cheaply when occupancy ≥ break-even. Adaptivity changed **cost**, never **content**. The mode choice therefore needed no accuracy argument, only a cost argument.

## 2. The proposed Stage 2 variants, judged by the same criterion

| Variant | Changes content? | Verdict |
|---|---|---|
| **G1. Block-vs-event update path** (E in candidates). Dense blocks go through the patch accumulator and tiled RMW; sparse events go through the per-event RMW | **No.** Same cells receive the same commutative increments | **Genuine opportunity.** Same structure as Stage 1. Needs a break-even analysis (patch RMW cost vs n × per-event RMW) and possibly hysteresis |
| **G2. Shared transform per block** (anchor + Jacobian offsets) | Tiny: linearization over 4 px is ~T² with T = 4, negligible vs warp-grid error | Accept. Its exactness should be shown, not assumed |
| **G3. Binning 2×2/4×4 under load** (reduce spatial precision) | **Yes.** Accuracy depends on scene activity | Reject as an automatic mode. It makes the map non-stationary in resolution; e.g. a busy region renders blurrier than a quiet one, which inverts what the user cares about. It is also hard to verify: the golden model must replicate the exact mode trace |
| **G4. Coarse world tile update instead of cells under load** | Yes | Reject, for the same reason as G3 |
| **G5. Motion-adaptive frame/time grouping** (share orientation across sub-frames at slow ω) | Yes, by ω·Δt | Not needed. DELTA already gives one timestamp per frame. The *opposite* (per-row time interpolation at fast ω) is the useful knob, and it is a function of ω, not traffic |
| **G6. Overload drop/merge policy** (when the memory queue is full: merge repeats or drop with accounting) | Yes, but only under overload | **Accept as an explicit robustness policy** with counters, not as a "precision mode". Stage 1's question "do you send or drop when a burst exceeds capacity?" (Q22) maps here |

## 3. Is the traffic-adaptive mapper justified?

- **Actually justified:** G1 (+G2). It is the Stage 2 analogue of Model2. Its value depends on *block occupancy in real data* and *world cell scale*. If most Group-AER groups carry 1–2 events, the block path rarely pays off and G1 is redundant. **This is precisely what Experiment 03 must measure before RTL.**
- **Redundant:** a separate traffic estimator when the input packet type (sparse address vs group bitmap) already tells the mapper which path to use. The sensor's Group-AER format *is* the mode signal. Do not rebuild Model2's occupancy counter at sensor scale.
- **Dangerous for accuracy:** G3/G4.
- **Promising enough to test:** G1 vs a pure per-event path, on equal workloads, measuring RMW count, stall cycles, energy proxy, and bit-exact map equality.

## 4. If G1 is kept: the decision rule

```
use block path iff  cost_block(occupancy, footprint) < occupancy × cost_event
cost_block ≈ (#tile words touched ≤ 4, in parallel banks) × RMW + merge latency
cost_event ≈ 1 RMW (+ forwarding/stall)
```

As in Stage 1's physical break-even table, compute the break-even occupancy for each tile size k and world scale s, then compare with the measured occupancy histogram of real blocks. Hysteresis is only needed if the paths share hardware and switching has a cost. If both paths exist concurrently, route per packet with no mode state at all. That is simpler, and preferable.

## 5. Honest positioning for the report

"Stage 1 adapted *packet representation* to traffic. Stage 2 keeps the representation that the sensor already groups, and adapts the *memory-update granularity*, without changing map content. We rejected precision-adaptive mapping because it would make map accuracy depend on scene activity." That is a stronger story than forcing an adaptive mode, *provided* Experiment 03 shows the block path saves memory traffic.
