# E-lite Merger (`wm_elite_merger`)

## Purpose and limits

Combine updates of **one native group** that land in the **same physical memory word** into one read-modify-write.

- No 2-D block assembly, no cross-group buffering, no associative search.
- Basis: Exp04 measured a 47–59 % modelled RMW reduction at threshold 2 within native words for 4×4/8×8 world tiles. Exp05 defined the reference `merge_group_updates(..., threshold=2, tile_cells=4)`.

## Record format

A **record** is one RMW request:

| Field | Width | Meaning |
|---|---|---|
| `bank` | 2 | target bank |
| `word_addr` | `BANK_ADDR_W` | word inside the bank |
| `delta[c]` for c = 0..TILE_CELLS−1 | `DELTA_W` = 4 each | events to add to cell c (≤ 8 per group) |
| `delta_off[c]` (only `ACC_MODE = ONOFF_PACKED`) | 4 each | OFF-plane deltas. With this field `delta` means ON |
| `n_events` | 4 | sum of deltas (verification + counters) |

A single-event record is just a one-hot delta vector. **One record format serves merged and unmerged updates**, so the bank controller has only one path.

## State and algorithm: one open record (run merger)

State: `open = {valid, bank, word_addr, delta[], grp_tag, n_events}`.

Per input bundle (lane 0 event e0, then lane 1 event e1, in stream order), for each valid event e in order:

```
compatible(e) = open.valid && MERGE_EN && e.grp_tag == open.grp_tag
                && e.bank == open.bank && e.word_addr == open.word_addr
if compatible(e):  open.delta[e.cell] += 1 ; open.n_events += 1
else:              emit(open) if open.valid ; open := new record from e
on a cycle whose input bundle has no valid event, or carries FRAME_MARK:
                   emit(open) if open.valid ; open.valid := 0
```

- **At most 2 records are emitted per cycle**: one flush per event, and the idle/FRAME_MARK flush only happens on cycles without events.
- There is deliberately **no flush on `last_of_grp`**. That could add a third emission in a cycle. The next group's first event is incompatible by `grp_tag` and flushes the record anyway, so the record waits at most until the next event, idle cycle or frame mark.
- Emission goes to two output registers (`rec[0]`, `rec[1]`) that the router accepts atomically.
- Out-of-range events (`in_range = 0`, only possible if the contract allows it) are dropped with a counter and never merged.
- **Run merging ≠ set merging.** The open record folds *consecutive* same-word events. Codex's reference merges *any* same-word events inside the group. Within one 1×8 group, events are y-sorted and map along a short monotone world path, so a word left and later re-entered within ≤ 8 events should be rare. **The final memory contents are identical either way** (commutative unsigned/ON-OFF accumulation); only the RMW count can differ. Codex is asked to add a `run` mode to the reference so RMW counts can be compared exactly (`rtl_spec_summary.md` §D).

## Cases

| Case | Example | Action | Where |
|---|---|---|---|
| **A** same cell, same group | two pixels → one world cell | fold: `delta[c] += 1` (→ 2) | merger |
| **B** same word, different cells, same group | two cells of one 4×4 tile | fold into the same record: two delta entries | merger |
| **C** same bank, different words | — | separate records, both enqueued to that bank (dual enqueue) and served back-to-back | router + bank queue |
| **D** different banks | — | separate records, parallel | router |
| **E** different polarity | ON and OFF in one word | `UNSIGNED`: fold (polarity is ignored by the count). `ONOFF_PACKED`: fold into the same record using `delta`/`delta_off`. Both planes live in one physical word, so **polarity does not split the merge key** (unlike Exp04's separate-plane model, which lost 9–10 points of merge opportunity) | merger |
| same word, **different groups** | group boundary | not merged (scope rule). Separate records → same bank queue → RAW bypass keeps correctness | bank ctrl |

## Threshold semantics (exact)

`MERGE_THRESH = 2` means: **a record is emitted as a merged multi-event RMW when ≥ 2 events of the same native group, consecutive in stream order, target the same physical word; otherwise each event is its own record.**

- Counting scope: the current native group (`MERGE_SCOPE = GROUP`, ≤ 8 events). `MERGE_SCOPE = WORD` (≤ 16 events, both groups of a sensor word) is a parameter for experiments. It changes RMW counts but not memory contents.
- Compatibility: same `bank`, same `word_addr`, same `grp_tag`.
- When decided: incrementally, as each event arrives, with no look-ahead and no extra buffering beyond the one open record.
- Maximum events considered: 8 per record (`MERGE_SCOPE = GROUP`).
- **Why the parameter is "2" and not a free knob:**
  - The record format and bank path are identical for merged and single updates. Folding k ≥ 2 events into one record costs no more than one single-event RMW, so merging at k = 2 is always profitable here.
  - `MERGE_THRESH > 2` would only make sense if merged records used a costlier separate path. They do not in this design.
  - The RTL therefore implements threshold 2 as "fold when compatible", and `MERGE_EN = 0` (or `MERGE_THRESH > 8`) degenerates to per-event records, the **D2 baseline**.

## Stage 1 relationship (report story)

- Stage 1 Model2 sent a dense bitmap packet only when block occupancy reached the point where its physical-link cost (header + padding) fell below n sparse packets (`DENSE_ENTER_THRESHOLD`, break-even 2–3 events on a 16-bit link).
- E-lite applies the **same break-even rule to memory RMWs instead of link beats**: aggregate when the number of events sharing a word (occupancy) makes one aggregated access cheaper than n separate ones.
- With a uniform record format the break-even is n = 2. With a costlier aggregate path the threshold would rise, exactly as Model2's threshold depended on link width.
- **No Model2 RTL is instantiated.** The sensor already groups events (Group-AER), so Stage 1's packetizer would be redundant. What carries over is the decision principle and the break-even methodology, now measured on real traffic (Exp03 break-even tables) and on world addresses (Exp04).

## Verification invariants

- Σ `n_events` over emitted records == number of valid, in-range events that entered the merger.
- For every (bank, word, cell): Σ deltas emitted == number of events mapped to that cell (checked against the per-event scoreboard).
- No record is emitted twice under random back-pressure on the router side.
- `MERGE_EN = 0` ⇒ every record has `n_events = 1`.
