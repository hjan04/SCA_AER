"""Structural dispatch model for the RTL spec (Claude workspace).

Replays the real decoded event streams (exp03_cache/*.npz, stream order) and
counts, per frame, the issue cycles needed by candidate two-lane dispatch
rules, plus horizontal-interpolation reuse and grid-node reads. These are
cycle COUNTS for a 2-issue datapath with no memory stalls, not timing or PPA.

Rules (all issue at most 2 events/cycle):
  P_word      pairs only events of the same native sensor word
              -> cycles = sum_words ceil(n/2)
  P_cross     pairs any two consecutive events of a frame (ideal bound)
              -> cycles = ceil(N_frame/2)
  P_word_h1   same as P_word but a pair must share the T32 horizontal key
              (x, y>>5) (one shared horizontal-lerp unit)
  P_cross_h1  P_cross with the same shared-key restriction

Reuse key for horizontal interpolation: (frame, x, y>>5). One register holds
the last key's top/bottom vectors (stream order). Node reads per key change:
2 if same x and grid row advanced by exactly 1 (slide down the column, keep
the old bottom nodes as the new top), else 4.

Usage: python3 -I dispatch_model.py <out.csv> name=path.npz [...]
"""
import csv
import sys

import numpy as np

CLOCK_HZ = 100e6          # assumption carried from Stage 1 / Exp04
FRAME_US = 773.0          # measured frame period (Exp03)
CHUNK = 104


def runs_ceil_half(keys):
    """sum over runs of equal consecutive keys of ceil(run_len/2)."""
    if keys.size == 0:
        return 0
    brk = np.flatnonzero(np.concatenate(([True], keys[1:] != keys[:-1],
                                         [True])))
    ln = np.diff(brk)
    return int(((ln + 1) // 2).sum())


def main():
    out = sys.argv[1]
    rows = []
    for arg in sys.argv[2:]:
        name, path = arg.split("=", 1)
        d = np.load(path)
        fr_all = d["frame"]
        x_all = d["x"]
        y_all = d["y"]
        w_all = d["word"]
        nf = int(fr_all.max()) + 1
        cyc = {k: np.zeros(nf, np.int64) for k in
               ("P_word", "P_cross", "P_word_h1", "P_cross_h1")}
        ev_f = np.bincount(fr_all, minlength=nf)
        popc_hist = np.zeros(17, np.int64)
        key_changes = 0
        node_reads = 0
        straddle_words = 0
        two_group_words = 0
        n_words = 0
        for c0 in range(0, nf, CHUNK):
            i0, i1 = np.searchsorted(fr_all, [c0, min(nf, c0 + CHUNK)])
            if i1 <= i0:
                continue
            fr = fr_all[i0:i1].astype(np.int64)
            x = x_all[i0:i1].astype(np.int64)
            y = y_all[i0:i1].astype(np.int64)
            w = w_all[i0:i1].astype(np.int64)
            gy = y >> 5
            hkey = (fr * 1024 + x) * 32 + gy
            # per-word popcount
            wb = np.flatnonzero(np.concatenate(([True], w[1:] != w[:-1],
                                                [True])))
            wn = np.diff(wb)
            popc_hist += np.bincount(np.minimum(wn, 16), minlength=17)
            n_words += wn.size
            wfr = fr[wb[:-1]]
            np.add.at(cyc["P_word"], wfr, (wn + 1) // 2)
            # words whose events span two T32 rows
            gmin = np.minimum.reduceat(gy, wb[:-1])
            gmax = np.maximum.reduceat(gy, wb[:-1])
            straddle_words += int((gmax != gmin).sum())
            ymin = np.minimum.reduceat(y >> 3, wb[:-1])
            ymax = np.maximum.reduceat(y >> 3, wb[:-1])
            two_group_words += int((ymax != ymin).sum())
            # P_cross: ceil(N/2) per frame
            nfc = np.bincount(fr - c0, minlength=min(nf, c0 + CHUNK) - c0)
            cyc["P_cross"][c0:c0 + nfc.size] += (nfc + 1) // 2
            # shared-key rules: runs of equal key
            for f in np.unique(fr):
                j0, j1 = np.searchsorted(fr, [f, f + 1])
                cyc["P_word_h1"][f] += runs_ceil_half(
                    w[j0:j1] * 64 + gy[j0:j1])
                cyc["P_cross_h1"][f] += runs_ceil_half(hkey[j0:j1])
            # reuse register + sliding node fetch (stream order, per frame)
            chg = np.concatenate(([True], hkey[1:] != hkey[:-1]))
            key_changes += int(chg.sum())
            slide = np.zeros_like(chg)
            slide[1:] = chg[1:] & (fr[1:] == fr[:-1]) & (x[1:] == x[:-1]) & \
                (gy[1:] == gy[:-1] + 1)
            node_reads += int(2 * slide.sum() + 4 * (chg & ~slide).sum())
        n = int(fr_all.size)
        valid = ev_f > 0
        budget = CLOCK_HZ * FRAME_US * 1e-6
        row = dict(dataset=name, events=n, words=n_words,
                   events_per_word=n / n_words,
                   words_two_groups_frac=two_group_words / n_words,
                   words_straddling_T32_row_frac=straddle_words / n_words,
                   hkey_change_per_event=key_changes / n,
                   hlerp_reduction_vs_per_event=1 - key_changes / n,
                   node_reads_per_event=node_reads / n,
                   node_read_reduction_vs_4_per_event=1 - node_reads / (4 * n),
                   cycle_budget_per_frame=budget)
        for k, c in cyc.items():
            cv = c[valid]
            row[f"{k}_issue_eff"] = n / (2 * cv.sum())
            row[f"{k}_frame_cycles_p95"] = float(np.percentile(cv, 95))
            row[f"{k}_frame_cycles_max"] = int(cv.max())
            row[f"{k}_util_max"] = float(cv.max() / budget)
            row[f"{k}_frames_over_budget"] = int((cv > budget).sum())
        for i, v in enumerate(popc_hist):
            row[f"popcount_{i}"] = int(v)
        rows.append(row)
        print(name, {k: (round(v, 4) if isinstance(v, float) else v)
                     for k, v in row.items() if not k.startswith("popcount")},
              flush=True)
    keys = list(rows[0].keys())
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=keys)
        wr.writeheader()
        for r in rows:
            wr.writerow({k: (f"{v:.6g}" if isinstance(v, float) else v)
                         for k, v in r.items()})


if __name__ == "__main__":
    main()
