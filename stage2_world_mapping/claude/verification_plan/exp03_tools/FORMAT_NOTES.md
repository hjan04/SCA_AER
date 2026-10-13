# DELTA `.dvs` (S5KRC1S) word format: how it was derived

## Source of truth

- No format specification is distributed with DELTA SDK v1.0.0 (only binaries, settings files, and the viewer README). The online NRV API docs describe only the *decoded* outputs: ClassicEvent / CompactEvent / frameTimestamp.
- The word layout in `dvs_decode.py` was reconstructed by disassembling the SDK's own parser in `~/DELTA_SDK-1.0.0/Linux/x64/libDELTA_SDK.so`:
  - `PacketParser::S5KRC1SDataProcess(DVSPacket*)` @ 0x24340 (word dispatch);
  - `PacketParser::AnalyzeData(InputArg&, unsigned mask, int base)` @ 0x24120 (mask → pixel coordinates);
  - `PacketParser::ComposeTimestampUs(unsigned, unsigned)` @ 0x240c0.
- Nothing was executed from the SDK. The disassembly was only read.

## Layout (byte order as stored in the file: b0 b1 b2 b3)

| Condition | Meaning | Fields |
|---|---|---|
| `b0 & 0x80` | event word | `g = ((b0&1)<<6) \| (b1>>2)`; `off = (b0&0x7C)>>2`; `b3` = mask of group g, polarity `b1&1`; `b2` = mask of group `g±off`, polarity `(b1>>1)&1` |
| `(b0&0x7C)==0x04` | column address | `col = ((b2&7)<<8) \| b3`; `flag = b1>>7` selects `g−off` instead of `g+off` |
| `(b0&0x7C)==0x08`, `b1` bit7 = 0 | coarse time | `V = ((b1&0x3F)<<16) \| (b2<<8) \| b3` |
| `(b0&0x7C)==0x08`, `b1` bit7 = 1 | fine time | `F = ((b2&3)<<8) \| b3`; the SDK composes `V·k1 + F·k0` (doubles, set by `SetTimestampScale`) |
| `(b0&0x7C)==0x0C` | frame end | — |
| `b0 = 0x7F` | register/header words at file start | ignored |
| `b0` bit1 | sensor channel (stereo) | always 0 in these files, except header words |

AnalyzeData emits one event per set mask bit, taking bits **LSB first** (`tzcnt`). The packed coordinate is `((base + bit) << 16) | address`, with `base = 8·group`. The bounds checks are `base+7 < field@0x5C` and `address < field@0x58`, i.e. `SetResolution(w, h)` limits. Decoded: `address` ranges 0..959 (column) and `8·group+bit` stays below 720. Hence **x = column word, y = 8·group + bit**.

## Checks performed on the actual files

- Column values never exceed 959. Coarse time values increase by 1 per ~1 ms. Fine time cycles in steps of ~773 µs modulo 1000 (max 999). Together these are consistent with `t_us = V·1000 + F` and a frame period of ≈ 0.773 ms (≈ 1294 FPS; the organizer's viewer showed 1291 FPS).
- About 2,060 frame-end words per ~1.59 s recording.
- The column flag (`b1` bit7) is never set in the three files, so the second group is always `g + off`.
- Visual check: `exp03_results/decode_check_accumulated.png` (accumulated event image per recording). If vertical structures (rods) appear vertical, x/y assignment and the bit order are right.

## Limits (state these in any report)

- The scale `t_us = V·1000 + F` is inferred from the sensor register comments (`to_scnt0` = 1 µs event clock, `to_scnt1` = 999 → 1 ms) plus the observed value ranges. The exact SDK doubles at offsets 0x40/0x48 were not read.
- **Polarity meaning** (whether bit = 1 is ON or OFF) is not determinable from the parser. Results label polarity as `p1` / `p0`.
- The playback-skip logic and stereo handling in the parser were not reproduced. They are irrelevant for single-sensor full-file decoding.
- This decoder is not an NRV-endorsed tool. A cross-check against the viewer's HDF5 export (GUI) is still recommended once someone can run the viewer interactively.
