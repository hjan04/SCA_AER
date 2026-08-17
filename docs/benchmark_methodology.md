# Baseline Benchmark Methodology

This document defines the Stage 2 baseline-only benchmark flow.

## Scope

Stage 2 characterizes the conventional baseline AER using reproducible traces
and RTL simulation. It does not implement adaptive AER, dense packet encoding,
CSV comparison against adaptive RTL, or Cadence synthesis.

## Trace Format

Each benchmark input is an explicit trace file preserved under
`traces/generated/`.

```text
event_id,cycle,x,y,polarity
```

Example:

```text
0,10,3,5,1
1,15,7,2,0
2,15,8,2,1
3,15,9,2,1
```

Multiple rows with the same cycle are simultaneous input events. The trace
driver groups those rows into one `pixel_event_valid_i` vector and one
`pixel_event_pol_i` vector before the corresponding clock edge.

If a trace contains multiple events for the same pixel in the same cycle, the
single-bit pixel input cannot represent all of them. The driver presents one
event for that pixel and counts the other same-cycle duplicates as capture loss.

## Reproducibility

Trace generation is handled by:

```text
scripts/sweep_baseline_traffic.py
```

Every random traffic run has an explicit seed. The seed, traffic type, variant,
offered rate, ACK delay, trace path, and result path are stored in generated
CSV/log artifacts.

The Stage 2 full sweep writes:

```text
traces/generated/stage2/
results/csv/runs/stage2/
results/raw/stage2/
results/waves/stage2/
```

## Traffic Classes

Implemented traffic classes:

- `sparse`: low-rate uniform random reference traffic.
- `uniform`: uniform random location traffic over a rate sweep.
- `poisson`: discrete-time Poisson-like arrivals with lambda in events/cycle.
- `hotspot`: 80% of events inside a configurable 4x4 region, 20% elsewhere.
- `burst`: quiet background traffic plus a high-rate burst interval.
- `simultaneous`: many unique pixels asserted in exactly one cycle.
- `locality`: same approximate offered rate concentrated into 16x16, 8x8,
  4x4, and 2x2 regions.

The default full Stage 2 sweep uses `X_SIZE=16`, `Y_SIZE=16`,
`5000` injection cycles, and three seeds for uniform, Poisson, hotspot, and
locality random cases.

## Output Sink

The reusable sink is:

```text
tb/common/tb_output_sink.sv
```

`ACK_DELAY_CYCLES=0` means the sink asserts ACK at the first negative clock edge
after observing `aer_req_o` high. With the current baseline four-phase FSM, a
saturated minimum-delay run completes one event about every three clock cycles.

Fixed-delay ACK cases use:

```text
ACK_DELAY_CYCLES = 1, 2, 4, 8
```

These runs measure sensitivity to output backpressure without changing the
input trace model.

## Scoreboard And Matching

The benchmark scoreboard mirrors the approved baseline capture semantics:

```text
one pending bit per pixel
one polarity bit per pixel
```

For each generated input event:

- if the pixel is not pending, the event is representable and becomes pending;
- if the pixel is already pending and is not accepted in that same cycle, the
  event is counted as capture loss;
- if the old event is accepted in the same cycle, the new event is captured.

Accepted output packets are decoded as:

```text
{polarity, y, x}
```

The output is matched against the pending model entry for that pixel and
polarity. Successfully matched outputs contribute to transmitted-event and
latency metrics. Unexpected or duplicate outputs are recorded in the CSV `notes`
field.

## Drain Behavior

After the injection window ends, input events stop. The simulation continues
until either:

```text
all modeled pending events are transmitted and the DUT is idle
```

or:

```text
MAX_DRAIN_CYCLES is reached
```

Events still pending after the timeout are counted as `undrained_at_end`.

## Metrics

Each benchmark run writes one CSV row with:

```text
architecture,
traffic_type,
traffic_variant,
seed,
x_size,
y_size,
clock_cycles_injection,
clock_cycles_total,
offered_events_per_cycle,
generated_events,
captured_events,
transmitted_events,
capture_loss,
undrained_at_end,
total_loss,
event_loss_rate,
successful_handshakes,
cycles_per_handshake,
throughput_injection_window,
throughput_full_run,
average_latency_cycles,
maximum_latency_cycles,
p95_latency_cycles,
bits_transmitted,
bits_per_event,
output_req_high_cycles,
output_utilization,
ack_delay_cycles,
notes
```

Definitions:

```text
latency = accepted_output_cycle - input_generation_cycle
offered_events_per_cycle = generated_events / injection_cycles
throughput_injection_window = events accepted during injection / injection_cycles
throughput_full_run = transmitted_events / total cycles including drain
total_loss = generated_events - transmitted_events
event_loss_rate = total_loss / generated_events
bits_transmitted = transmitted_events * EVENT_W
bits_per_event = bits_transmitted / transmitted_events
output_utilization = cycles with REQ high / total cycles
```

For the `16x16` baseline, `EVENT_W = 9`, so `bits_per_event` should remain 9
when at least one event is transmitted.

`cycles_per_handshake` is stored as total benchmark cycles divided by successful
handshakes. In saturated cases this approaches the actual service interval; in
sparse cases it also includes idle time.

## Saturation Definition

Maximum sustainable input event rate is defined before analysis as the highest
tested uniform offered load where:

```text
event_loss_rate <= 1%
and
throughput_full_run >= 95% of offered_events_per_cycle
```

The same rule should be reused for Stage 3 adaptive comparisons unless it is
explicitly revised before running adaptive data.

## Reproduction Commands

Run the Stage 1 regression:

```bash
scripts/run_baseline_sim.sh
```

Run a small benchmark smoke test:

```bash
scripts/sweep_baseline_traffic.py --preset smoke
```

Run the full Stage 2 baseline sweep:

```bash
scripts/sweep_baseline_traffic.py --preset stage2
```

Regenerate the combined CSV, plots, and analysis from existing per-run CSVs:

```bash
scripts/summarize_baseline_results.py \
  --input-dir results/csv/runs/stage2 \
  --output-csv results/csv/baseline_summary.csv
```
