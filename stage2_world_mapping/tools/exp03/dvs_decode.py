"""Minimal decoder for NRV DELTA (S5KRC1S, single-sensor) raw .dvs files.

Exp03 analysis helper (Claude workspace). Read-only on the input file.

Word format was reconstructed by disassembling the distributed SDK binary
(`libDELTA_SDK.so`, functions `PacketParser::S5KRC1SDataProcess` and
`PacketParser::AnalyzeData`, DELTA SDK v1.0.0). It is NOT an official spec;
see exp03_tools/FORMAT_NOTES.md for the derivation and its limits.

Each 32-bit word = bytes b0 b1 b2 b3 in file order.
  b0 bit7 = 1  -> EVENT word
      group g   = ((b0 & 1) << 6) | (b1 >> 2)      (8-pixel group along y)
      off       = (b0 & 0x7C) >> 2                  (second-group offset)
      b3        = 8-bit mask for group g,       polarity = b1 & 1
      b2        = 8-bit mask for group g+off,   polarity = (b1 >> 1) & 1
                  (g-off if the column word's b1 bit7 flag is set)
      pixel     = (x = current column, y = 8*group + bit), bit 0 = LSB
  b0 bit7 = 0, type = b0 & 0x7C:
      0x04 COLUMN word: column = ((b2 & 7) << 8) | b3 ; flag = b1 >> 7
      0x08 TIME word:   b1 bit7 == 0 -> coarse V = ((b1&0x3F)<<16)|(b2<<8)|b3
                        b1 bit7 == 1 -> fine   F = ((b2&3)<<8)|b3
                        (sensor register setting: 1 us event clock, 1 ms coarse
                         -> interpreted as t_us = V*1000 + F; ASSUMPTION)
      0x0C FRAME-END word
      0x7C register/header words at file start (ignored)
  b0 bit1 = sensor channel (stereo); single-sensor files use channel 0.

Usage:
  python3 -I dvs_decode.py <in.dvs> <out.npz>
Output arrays (one row per pixel event, in file/stream order):
  frame (int32, index of frame = number of FRAME-END words seen before),
  t_us (int64, last composed timestamp), x (int16), y (int16), p (int8),
  word (int32, index of the source event word), slot (int8: 0=b3 group, 1=b2 group)
"""
import sys
import numpy as np

H_LIMIT = 720   # SDK checks group_base+7 < height; events beyond are dropped
W_LIMIT = 960


def decode(path):
    raw = np.fromfile(path, dtype=np.uint8)
    n = len(raw) // 4
    w = raw[: n * 4].reshape(n, 4)
    b0, b1, b2, b3 = (w[:, i].astype(np.int32) for i in range(4))
    is_ev = b0 >= 0x80
    typ = np.where(is_ev, -1, b0 & 0x7C)
    ch = (b0 >> 1) & 1
    idx = np.arange(n, dtype=np.int64)

    def ffill(mask, values, default=-1):
        last = np.where(mask, idx, -1)
        last = np.maximum.accumulate(last)
        out = np.where(last >= 0, values[np.maximum(last, 0)], default)
        return out

    is_col = typ == 0x04
    col_val = ((b2 & 7) << 8) | b3
    col_flag = b1 >> 7
    cur_col = ffill(is_col, col_val)
    cur_flag = ffill(is_col, col_flag, 0)

    is_t = typ == 0x08
    is_hi = is_t & ((b1 & 0x80) == 0)
    is_lo = is_t & ((b1 & 0x80) != 0)
    V = ((b1 & 0x3F) << 16) | (b2 << 8) | b3
    F = ((b2 & 3) << 8) | b3
    cur_V = ffill(is_hi, V)
    t_lo = np.where(is_lo, cur_V.astype(np.int64) * 1000 + F, -1)
    cur_t = ffill(is_lo, t_lo)

    frame_no = np.cumsum(typ == 0x0C)

    ev = np.where(is_ev & (ch == 0))[0]
    g = ((b0[ev] & 1) << 6) | (b1[ev] >> 2)
    off = (b0[ev] & 0x7C) >> 2
    g2 = np.where(cur_flag[ev] != 0, g - off, g + off)
    # Expand both 8-bit masks of every event word in one (nev, 16) bit array.
    # Row-major nonzero() then yields events directly in stream order:
    # word order, then slot 0 (b3 / group g) before slot 1 (b2 / group g+off),
    # then LSB-first bit order, exactly as the SDK parser emits them.
    masks = np.stack([b3[ev], b2[ev]], axis=1).astype(np.uint8)   # (nev, 2)
    bits = np.unpackbits(masks, axis=1, bitorder="little")        # (nev, 16)
    del masks
    r, k = np.nonzero(bits)
    del bits
    r = r.astype(np.int32)
    k = k.astype(np.int8)
    slot = (k >= 8).astype(np.int8)
    bit = (k & 7).astype(np.int16)
    grp = np.where(slot == 0, g[r], g2[r])
    pol = np.where(slot == 0, b1[ev][r] & 1, (b1[ev][r] >> 1) & 1).astype(np.int8)
    wi = ev[r]
    xs = cur_col[wi]
    ys = grp * 8 + bit
    ok = (grp >= 0) & (grp * 8 + 7 < H_LIMIT) & (xs >= 0) & (xs < W_LIMIT)
    res = {
        "frame": frame_no[wi][ok].astype(np.int32),
        "t_us": cur_t[wi][ok].astype(np.int64),
        "x": xs[ok].astype(np.int16),
        "y": ys[ok].astype(np.int16),
        "p": pol[ok],
        "word": wi[ok].astype(np.int32),
        "slot": slot[ok],
    }
    n_dropped = int((~ok).sum())
    meta = {
        "n_words": n,
        "n_event_words": int(is_ev.sum()),
        "n_column_words": int(is_col.sum()),
        "n_time_words": int(is_t.sum()),
        "n_frame_end": int((typ == 0x0C).sum()),
        "n_header_words": int((typ == 0x7C).sum()),
        "n_ch1_words": int((ch == 1).sum()),
        "col_flag_set": int((is_col & (col_flag != 0)).sum()),
        "dropped_out_of_range_groups": n_dropped,
    }
    # frame-level table: frame index -> timestamp, word span
    fe = np.where(typ == 0x0C)[0]
    frame_t = cur_t[np.minimum(fe + 3, n - 1)]   # ts words follow frame-end
    meta_arrays = {"frame_end_word": fe.astype(np.int64),
                   "frame_end_t_us_after": frame_t.astype(np.int64),
                   "column_word_frame": frame_no[is_col].astype(np.int32),
                   "column_word_col": col_val[is_col].astype(np.int16),
                   "column_word_index": idx[is_col].astype(np.int64),
                   "event_word_index": ev.astype(np.int64),
                   "event_word_group": g.astype(np.int16),
                   "event_word_off": off.astype(np.int16)}
    return res, meta, meta_arrays


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    res, meta, extra = decode(src)
    np.savez_compressed(dst, **res, **extra,
                        meta_keys=np.array(list(meta.keys())),
                        meta_vals=np.array([str(v) for v in meta.values()]))
    print(meta, "pixel events:", len(res["x"]))
