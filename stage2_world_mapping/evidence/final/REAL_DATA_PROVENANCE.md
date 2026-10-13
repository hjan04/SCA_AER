# Recovered Sept 22 recording provenance and decode validation

## Immutable source files

The two raw recordings were read only. Their current byte sizes and SHA-256 values are:

| Recording | Bytes | SHA-256 |
|---|---:|---|
| `real_data/2026-09-22-16-42-32-DELTA.dvs` | 99,398,908 | `3f0e2021e77e7244a84a3caa2163b59e8d6d9dfd500dc55785517c602358a643` |
| `real_data/2026-09-22-16-42-44-DELTA.dvs` | 111,277,936 | `dd7521e8eef54b125d4564c52db880cd69491591cb2fa2f8aa3f669bc1e42db8` |

## Restored original Exp03 tools

The restored sources identify themselves as the Exp03 analysis helper and the original driver (`copy-extract -> decode -> analyze -> merge`). The driver calls `dvs_decode.py` to create one NPZ per recording, then `exp03_analyze.py` processes the decoded arrays in frame-aligned chunks. The original decoder itself uses `numpy.fromfile` and expands a whole recording at once. To avoid that memory-heavy path on the full files, `final_evidence/stream_exp03_recordings.py` invokes the restored decoder on bounded one-million-word chunks. It carries the decoder's column, timestamp, and frame state between chunks and rebases indexes; no new word format or event ordering was introduced.

| Original tool | SHA-256 |
|---|---|
| `exp03_tools/FORMAT_NOTES.md` | `4f60cdc72b1e2c4a65f4becab53296739d5b3e28ee8e7ea474126fc0bde48650` |
| `exp03_tools/dvs_decode.py` | `562a283f904a073cc37955f821295e8302057102bc3efcd95dbc2122f8c35433` |
| `exp03_tools/exp03_analyze.py` | `cfb416f8259369eff2298fee239db93989b0ad2f2b26343968b8a9309bbe635b` |
| `exp03_tools/run_exp03.sh` | `16d5e4b4f97fe3ae0a0be9a28828bd1d6466716b7f1ae069ccd7afccb42f8c9f` |

Format assumptions and known limitations are recorded in `exp03_tools/FORMAT_NOTES.md`: 4-byte words in stored byte order; event masks expanded slot A then slot B and LSB first; coordinates are 960 columns by 720 rows; timestamps use the documented inferred `V*1000+F` microsecond composition; polarity is reported as p0/p1 because physical ON/OFF meaning is unknown. The column offset flag was clear in both recordings. The decoder reported one out-of-range contribution in the first recording and none in the second.

The compact streaming run is reproducible with `python3 final_evidence/stream_exp03_recordings.py real_data/2026-09-22-16-42-32-DELTA.dvs real_data/2026-09-22-16-42-44-DELTA.dvs`; it processes one recording at a time and reports word progress as it goes. RTL vector generation is `python3 final_evidence/build_recovered_peak_scenarios.py`.

## Validation

Before full processing, the original decoder decoded the first 2,000,000 words (8 MB) of each recording. File 16:42:32 yielded 4,717,236 in-range pixel events in frames 0–420; file 16:42:44 yielded 4,921,014 in frames 0–309. Both prefixes covered x=0..959 and y=0..719 and contained both p0 and p1. Their parser counts and channel/column-flag behavior agreed with the format notes. A separate 500,000-word chunk cross-check matched the original whole-prefix decoder exactly for frame, timestamp, x, y, polarity, source event-word index, and slot.

The project’s compact Sept22b archive, `reference/real_traffic/sept22b_f900_f901.npz` (SHA-256 `028dd243ea723b051be4c4d9c2167396b997b265d9001fa83456f8c28637c68c`), independently matches the restored decoder at frames 900 and 901 of the 16:42:44 file:

| Frame | Events | Native event words | p0 / p1 | Coordinate range |
|---:|---:|---:|---:|---|
| 900 | 69,460 | 18,522 | 32,938 / 36,522 | x 0..959, y 0..719 |
| 901 | 70,115 | 18,690 | 34,489 / 35,626 | x 0..959, y 0..719 |

These exact counts, word groupings, polarity counts, and coordinate ranges validate the recovered interpretation against existing project data.

## Full decode totals

| Recording | Frame IDs represented in CSV | Nonempty frames | Pixel events | Native event words | Median frame interval |
|---|---:|---:|---:|---:|---:|
| 16:42:32 | 2,063 | 2,057 | 75,340,608 | 22,980,715 | 773 us |
| 16:42:44 | 2,054 | 2,053 | 88,075,183 | 25,878,861 | 773 us |

`real_data_summary/sept22_frame_stats.csv` contains one row for every frame ID represented by the frame-end count, including zero-event frames. A frame interval is populated when consecutive frame-end timestamps are available; the recording’s initial partial frame has no preceding boundary. Event rate is event count divided by that frame’s recorded interval, not a per-event physical timestamp reconstruction. Aggregate and peak details are in `PEAK_FRAME_RTL.md` and `real_data_summary/peak_selection.json`.

The files cover only the two recovered Sept 22 recordings. They do not establish a maximum over the unavailable Sept 15 recording.
