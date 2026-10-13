"""Experiment 03: real-traffic locality / block-amortization / memory-update analysis.

Claude workspace analysis script. Inputs are npz files produced by dvs_decode.py.
All results are IMAGE-SPACE measurements and proxies. No pose is applied, so
nothing here is an actual world-memory collision rate.

Memory-bounded design: events are processed in frame-aligned chunks
(CHUNK_FRAMES, a multiple of every multi-frame window), and every
distribution is accumulated as a histogram. Percentiles are read from the
histograms. (The first version materialised ~87M-event int64 arrays and
exhausted the 15 GB WSL VM.)

Usage (one dataset per process, then merge):
  python3 -I exp03_analyze.py one   <state.pkl> name=path.npz
  python3 -I exp03_analyze.py merge <out_dir> state1.pkl [state2.pkl ...]
"""
import csv
import os
import pickle
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

W, H = 960, 720
WH = W * H
SHAPES = [(1, 8), (2, 2), (4, 4), (8, 8), (16, 16), (32, 32), (4, 8), (8, 4)]
WIN_SHAPES = [(1, 8), (4, 4), (8, 8), (16, 16)]
WINDOW_FRAMES = [1, 4, 13]          # 13 frames ~ 10 ms at 0.773 ms/frame
CHUNK_FRAMES = 104                  # multiple of 4 and 13
BREAK_SHAPES = [(1, 8), (4, 4), (8, 8), (16, 16)]
BREAK_OVERHEAD = [1.0, 2.0, 4.0]    # C_block in units of C_event
BREAK_INCR = [0.0, 0.25, 0.5]       # per-event incremental cost inside a group
RMW_PER_BLOCK = [1, 2, 4]           # words touched per occupied block
LOC_BLOCKS = [4, 8, 16]
BANKS = ["2bank_xpar", "2bank_ypar", "4bank_xy_par", "4bank_ylow2",
         "4bank_tile4_par"]
DIST_CAP = 1 << 20


def hadd(acc, key, h):
    """Accumulate histogram h into acc[key] (growing as needed)."""
    a = acc.get(key)
    if a is None or a.size < h.size:
        nb = np.zeros(max(h.size, 0 if a is None else a.size), np.int64)
        if a is not None:
            nb[:a.size] += a
        a = nb
    a[:h.size] += h
    acc[key] = a


def hpct(h, q):
    c = np.cumsum(h)
    if c[-1] == 0:
        return float("nan")
    return float(np.searchsorted(c, q / 100.0 * c[-1]))


def hstats(h):
    v = np.arange(h.size)
    tot = h.sum()
    return dict(mean=float((v * h).sum() / tot), p50=hpct(h, 50),
                p90=hpct(h, 90), p95=hpct(h, 95), p99=hpct(h, 99),
                max=float(np.flatnonzero(h).max()))


def arrstats(a):
    a = np.asarray(a, dtype=np.float64)
    return dict(mean=float(a.mean()), p50=float(np.percentile(a, 50)),
                p90=float(np.percentile(a, 90)),
                p95=float(np.percentile(a, 95)),
                p99=float(np.percentile(a, 99)), max=float(a.max()))


def bank_of(name, x, y):
    if name == "2bank_xpar":
        return x & 1, 2
    if name == "2bank_ypar":
        return y & 1, 2
    if name == "4bank_xy_par":
        return (x & 1) * 2 + (y & 1), 4
    if name == "4bank_ylow2":
        return y & 3, 4
    return ((x // 4) & 1) * 2 + ((y // 4) & 1), 4


def analyze_one(name, path):
    d = np.load(path)
    fr_all = d["frame"]                     # int32, nondecreasing
    t_all = d["t_us"]
    n = int(fr_all.size)
    nf = int(fr_all.max()) + 1
    epf_all = np.bincount(fr_all, minlength=nf)
    first = np.searchsorted(fr_all, np.arange(nf))
    has = epf_all > 0
    f_ids = np.flatnonzero(has)
    f_t = t_all[first[has]]
    # Files start mid-frame: events before the first TIME words have t = -1.
    # Exclude such partial frames from all timing statistics.
    tvalid = f_t >= 0
    n_untimed_frames = int((~tvalid).sum())
    n_untimed_events = int(epf_all[has][~tvalid].sum())
    del t_all
    x_all = d["x"]
    y_all = d["y"]
    p_all = d["p"]
    meta = dict(zip(d["meta_keys"].tolist(), d["meta_vals"].tolist()))
    colw_frame = d["column_word_frame"]
    colw_col = d["column_word_col"].astype(np.int64)
    n_event_words = int(d["event_word_index"].size)
    n_frame_end = int(d["frame_end_word"].size)

    H_ = {}           # histograms
    S_ = {}           # scalar sums
    occ_per_win = {}  # list of occupied-blocks-per-window arrays
    skew = {b: [] for b in BANKS}
    pix_count = np.zeros(WH, np.int64)
    pix_active_frames = np.zeros(WH, np.int64)

    def sadd(k, v):
        S_[k] = S_.get(k, 0) + v

    for c0 in range(0, nf, CHUNK_FRAMES):
        c1 = min(nf, c0 + CHUNK_FRAMES)
        i0, i1 = np.searchsorted(fr_all, [c0, c1])
        if i1 <= i0:
            continue
        fr = fr_all[i0:i1].astype(np.int64)
        x = x_all[i0:i1].astype(np.int64)
        y = y_all[i0:i1].astype(np.int64)
        p = p_all[i0:i1].astype(np.int64)
        pix = y * W + x
        kfp = fr * WH + pix
        same_f = fr[1:] == fr[:-1]
        # ---- pixel counts, active frames, same-pixel repeats
        pix_count += np.bincount(pix, minlength=WH)
        ufp, cfp = np.unique(kfp, return_counts=True)
        pix_active_frames += np.bincount(ufp % WH, minlength=WH)
        for win in WINDOW_FRAMES:
            if win == 1:
                cw = cfp
                nwin = np.unique(fr).size
            else:
                _, cw = np.unique((fr // win) * WH + pix, return_counts=True)
                nwin = np.unique(fr // win).size
            sadd(f"rep_w{win}", int((cw - 1).sum()))
            sadd(f"distinct_w{win}", int(cw.size))
            sadd(f"nwin_w{win}", int(nwin))
        # ---- block occupancy
        for (bw, bh) in SHAPES:
            nbx = (W + bw - 1) // bw
            nby = (H + bh - 1) // bh
            for win in WINDOW_FRAMES:
                if win > 1 and (bw, bh) not in WIN_SHAPES:
                    continue
                key = ((fr // win) * nby + y // bh) * nbx + x // bw
                uk, cnt = np.unique(key, return_counts=True)
                hadd(H_, ("occ", bw, bh, win), np.bincount(cnt))
                wid = uk // (nbx * nby)
                occ_per_win.setdefault((bw, bh, win), []).append(
                    np.unique(wid, return_counts=True)[1])
                if (bw, bh, win) == (4, 4, 1):
                    s1 = np.bincount(np.searchsorted(uk, key), weights=p,
                                     minlength=uk.size)
                    mixed = (s1 > 0) & (s1 < cnt)
                    sadd("mixed4_blocks", int(mixed.sum()))
                    sadd("mixed4_events", int(cnt[mixed].sum()))
                    sadd("blocks4", int(cnt.size))
        # ---- consecutive-event locality (stream order)
        sadd("pairs", int(same_f.size))
        sadd("pairs_same_frame", int(same_f.sum()))
        for b in LOC_BLOCKS:
            bx, by = x // b, y // b
            same = same_f & (bx[1:] == bx[:-1]) & (by[1:] == by[:-1])
            neigh = same_f & (np.abs(bx[1:] - bx[:-1]) <= 1) & \
                (np.abs(by[1:] - by[:-1]) <= 1) & ~same
            sadd(f"same_b{b}", int(same.sum()))
            sadd(f"neigh_b{b}", int(neigh.sum()))
            brk = np.concatenate(([True], ~same, [True]))
            runs = np.diff(np.flatnonzero(brk))
            hadd(H_, ("run", b), np.bincount(runs))
            key = fr * 1_000_000 + by * 1000 + bx
            order = np.argsort(key, kind="stable")
            ks = key[order]
            ps = ks[1:] == ks[:-1]
            dist = np.minimum(np.diff(order)[ps], DIST_CAP)
            hadd(H_, ("reuse", b), np.bincount(dist))
            sadd(f"runs_b{b}", int(runs.size))
            sadd(f"fblocks_b{b}", int(np.unique(key).size))
        # ---- scan order (only consecutive pairs inside one frame)
        sadd("colmaj_nondec", int((np.diff(x * H + y)[same_f] >= 0).sum()))
        sadd("rowmaj_nondec", int((np.diff(pix)[same_f] >= 0).sum()))
        sadd("x_nondec", int((np.diff(x)[same_f] >= 0).sum()))
        sadd("colframe_pairs", int(np.unique(fr * 1000 + x).size))
        # ---- polarity
        sadd("p1", int(p.sum()))
        o = np.argsort(kfp, kind="stable")
        sp = kfp[o][1:] == kfp[o][:-1]
        sadd("opp_same_frame", int((sp & (p[o][1:] != p[o][:-1])).sum()))
        o2 = np.lexsort((fr, pix))
        sp2 = (pix[o2][1:] == pix[o2][:-1]) & (np.diff(fr[o2]) == 1)
        sadd("refire_next_same", int((sp2 & (p[o2][1:] == p[o2][:-1])).sum()))
        sadd("refire_next_opp", int((sp2 & (p[o2][1:] != p[o2][:-1])).sum()))
        # ---- banking (image space)
        for bname in BANKS:
            bank, nb = bank_of(bname, x, y)
            hadd(H_, ("bankload", bname), np.bincount(bank, minlength=nb))
            sadd(f"bankconf_{bname}",
                 int(((bank[1:] == bank[:-1]) & same_f).sum()))
            fb = np.bincount((fr - c0) * nb + bank,
                             minlength=(c1 - c0) * nb).reshape(-1, nb)
            fb = fb[fb.sum(1) > 0]
            skew[bname].append(fb.max(1) / (fb.sum(1) / nb))
        # ---- isolated-event (noise) proxy: no other event in the 3x3
        # neighbourhood of the same frame (either polarity)
        for f in range(c0, c1):
            j0, j1 = np.searchsorted(fr_all, [f, f + 1])
            if j1 <= j0:
                continue
            img = np.zeros((H + 2, W + 2), np.uint8)
            yy = y_all[j0:j1].astype(np.int64) + 1
            xx = x_all[j0:j1].astype(np.int64) + 1
            img[yy, xx] = 1
            nb = sum(img[yy + dy, xx + dx] for dy in (-1, 0, 1)
                     for dx in (-1, 0, 1) if (dy, dx) != (0, 0))
            sadd("isolated", int((nb == 0).sum()))
        sadd("events", int(i1 - i0))
        if (c0 // CHUNK_FRAMES) % 5 == 0:
            print(f"[{name}] frames {c0}-{c1} ok", flush=True)

    assert S_["events"] == n
    # ------------------------------------------------------------ rows
    rows = {k: [] for k in ("dataset", "rate", "occ", "loc", "pol", "brk",
                            "rmw", "bank", "hot", "order", "collide")}
    f_t = f_t[tvalid]
    dt = np.diff(f_t)
    dur_s = (f_t[-1] - f_t[0]) / 1e6 + float(np.median(dt)) / 1e6
    n_timed = n - n_untimed_events
    cols_per_frame = np.bincount(colw_frame)
    rows["dataset"].append(dict(
        dataset=name, file=os.path.basename(path),
        words=int(meta["n_words"]), event_words=n_event_words,
        column_words=int(colw_frame.size), frame_end_words=n_frame_end,
        frames_with_events=int(f_ids.size), pixel_events=n,
        duration_s=round(dur_s, 4),
        frame_period_us_median=float(np.median(dt)),
        frame_period_us_p1=float(np.percentile(dt, 1)),
        frame_period_us_p99=float(np.percentile(dt, 99)),
        fps_est=round(1e6 / float(np.median(dt)), 1),
        pixels_per_event_word=round(n / n_event_words, 3),
        column_words_per_frame_mean=round(float(cols_per_frame.mean()), 1),
        bytes_per_pixel_event=round(4 * int(meta["n_words"]) / n, 3),
        dropped_out_of_range=meta.get("dropped_out_of_range_groups", ""),
        untimed_partial_frames=n_untimed_frames,
        untimed_events=n_untimed_events,
        isolated_event_frac=S_["isolated"] / n))
    epf = epf_all[has][tvalid]
    rows["rate"].append(dict(dataset=name, metric="events_per_frame",
                             **arrstats(epf)))
    rows["rate"].append(dict(dataset=name, metric="events_per_sec_mean",
                             mean=n_timed / dur_s))
    rows["rate"].append(dict(dataset=name,
                             metric="events_per_sec_per_frame_basis",
                             **{k: v * 1e6 / float(np.median(dt))
                                for k, v in arrstats(epf).items()}))
    tt = f_t - f_t[0]
    window_series = {}
    for wms in (1, 5, 10):
        b = np.bincount(tt // (wms * 1000), weights=epf).astype(np.int64)
        window_series[wms] = b
        s = arrstats(b[:-1] if b.size > 1 else b)   # drop partial last window
        rows["rate"].append(dict(dataset=name,
                                 metric=f"events_per_{wms}ms_window", **s))
        rows["rate"].append(dict(dataset=name,
                                 metric=f"peak_events_per_sec_{wms}ms",
                                 max=s["max"] * 1000 / wms))
    amort = {}
    occ_hist = {}
    for (bw, bh) in SHAPES:
        for win in WINDOW_FRAMES:
            h = H_.get(("occ", bw, bh, win))
            if h is None:
                continue
            v = np.arange(h.size)
            nblk = int(h.sum())
            st = hstats(h)
            opw = np.concatenate(occ_per_win[(bw, bh, win)])
            row = dict(dataset=name, block=f"{bw}x{bh}", window_frames=win,
                       occupied_blocks_total=nblk,
                       occ_blocks_per_window_mean=float(opw.mean()),
                       occ_blocks_per_window_p95=float(np.percentile(opw, 95)),
                       ev_per_block_mean=st["mean"], ev_per_block_p50=st["p50"],
                       ev_per_block_p90=st["p90"], ev_per_block_p95=st["p95"],
                       ev_per_block_p99=st["p99"], ev_per_block_max=st["max"],
                       frac_blocks_single=float(h[1] / nblk) if h.size > 1 else 0.0)
            for k in (2, 4, 8, 16):
                row[f"frac_events_in_blocks_ge{k}"] = float(
                    (v[k:] * h[k:]).sum() / n)
            row["amortization_events_per_block"] = float(n / nblk)
            rows["occ"].append(row)
            if win == 1:
                amort[(bw, bh)] = n / nblk
                occ_hist[(bw, bh)] = h
            if win == 1 and (bw, bh) in BREAK_SHAPES:
                for beta in BREAK_OVERHEAD:
                    for a in BREAK_INCR:
                        nstar = beta / (1.0 - a)
                        above = v > nstar
                        always = ((beta + a * v) * h).sum() / n
                        adaptive = (np.minimum(v, beta + a * v) * h).sum() / n
                        rows["brk"].append(dict(
                            dataset=name, block=f"{bw}x{bh}",
                            block_overhead=beta, incr_cost=a,
                            breakeven_n=round(nstar, 3),
                            frac_blocks_above=float(h[above].sum() / nblk),
                            frac_events_in_blocks_above=float(
                                (v[above] * h[above]).sum() / n),
                            cost_ratio_always_grouped=float(always),
                            cost_ratio_adaptive=float(adaptive)))
            if (bw, bh) in BREAK_SHAPES:
                for k in RMW_PER_BLOCK:
                    rows["rmw"].append(dict(
                        dataset=name, block=f"{bw}x{bh}", window_frames=win,
                        words_per_block=k,
                        rmw_ratio_vs_per_event=float(
                            (np.minimum(v, k) * h).sum() / n)))
    for b in LOC_BLOCKS:
        hr, hd = H_[("run", b)], H_[("reuse", b)]
        rows["loc"].append(dict(
            dataset=name, block=f"{b}x{b}",
            p_next_same_block=S_[f"same_b{b}"] / S_["pairs_same_frame"],
            p_next_neighbor_block=S_[f"neigh_b{b}"] / S_["pairs_same_frame"],
            run_len_mean=hstats(hr)["mean"], run_len_p50=hpct(hr, 50),
            run_len_p95=hpct(hr, 95), run_len_max=hstats(hr)["max"],
            reuse_dist_p50=hpct(hd, 50), reuse_dist_p95=hpct(hd, 95),
            block_visits_per_frame_block_mean=S_[f"runs_b{b}"] /
            S_[f"fblocks_b{b}"]))
    cw_same = colw_frame[1:] == colw_frame[:-1]
    pf = S_["pairs_same_frame"]
    rows["order"].append(dict(
        dataset=name,
        colmajor_nondecreasing_frac=S_["colmaj_nondec"] / pf,
        colmajor_violation_frac=1 - S_["colmaj_nondec"] / pf,
        rowmajor_nondecreasing_frac=S_["rowmaj_nondec"] / pf,
        x_nondecreasing_frac=S_["x_nondec"] / pf,
        column_word_increasing_frac=float(
            (np.diff(colw_col)[cw_same] > 0).mean()),
        column_words_per_frame_mean=float(cols_per_frame.mean()),
        column_words_without_events_frac=1 - S_["colframe_pairs"] /
        colw_frame.size,
        frames=int(f_ids.size)))
    rows["pol"].append(dict(
        dataset=name, frac_p1=S_["p1"] / n, frac_p0=1 - S_["p1"] / n,
        frac_4x4_blocks_mixed=S_["mixed4_blocks"] / S_["blocks4"],
        frac_events_in_mixed_4x4=S_["mixed4_events"] / n,
        same_pixel_opposite_pol_same_frame=S_["opp_same_frame"] / n,
        pixel_refire_next_frame_same_pol=S_["refire_next_same"] / n,
        pixel_refire_next_frame_opp_pol=S_["refire_next_opp"] / n,
        note="next-frame refire undercounted at chunk edges (1 of 104 transitions)"))
    for win in WINDOW_FRAMES:
        rows["collide"].append(dict(
            dataset=name, window_frames=win,
            same_pixel_repeat_frac=S_[f"rep_w{win}"] / n,
            distinct_pixels_per_window_mean=S_[f"distinct_w{win}"] /
            S_[f"nwin_w{win}"]))
    # hot pixels
    pc = pix_count.reshape(H, W)
    af = pix_active_frames.reshape(H, W)
    flat = np.sort(pix_count)[::-1]
    k01 = int(round(0.001 * WH))
    k1 = int(round(0.01 * WH))
    pad = np.pad(pc, 1, mode="edge").astype(np.float64)
    neigh = np.stack([pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
                      for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                      if (dy, dx) != (0, 0)])
    nmed = np.median(neigh, axis=0)
    hot = (pc > 20 * np.maximum(nmed, 1)) & (af > 0.2 * f_ids.size)
    always_on = af > 0.9 * f_ids.size
    rows["hot"].append(dict(
        dataset=name, active_pixels=int((pc > 0).sum()),
        top0p1pct_pixels=k01, top0p1pct_event_share=float(flat[:k01].sum() / n),
        top1pct_pixels=k1, top1pct_event_share=float(flat[:k1].sum() / n),
        max_pixel_count=int(flat[0]),
        mean_count_active=float(pc[pc > 0].mean()),
        pixels_active_gt90pct_frames=int(always_on.sum()),
        gt90pct_frames_event_share=float(pc[always_on].sum() / n),
        hot_candidates_isolated_persistent=int(hot.sum()),
        hot_candidate_event_share=float(pc[hot].sum() / n),
        hot_rule="count>20x median(8-neighbors) AND active in >20% of frames"))
    for bname in BANKS:
        ld = H_[("bankload", bname)]
        sk = np.concatenate(skew[bname])
        rows["bank"].append(dict(
            dataset=name, scheme=bname, banks=int(ld.size),
            load_share=";".join(f"{v / ld.sum():.3f}" for v in ld),
            consecutive_pair_conflict=S_[f"bankconf_{bname}"] /
            S_["pairs_same_frame"],
            per_frame_skew_mean=float(sk.mean()),
            per_frame_skew_p95=float(np.percentile(sk, 95))))
    # decode-check image: 10 frames from the middle of the recording
    mid = int(np.median(f_ids))
    i0, i1 = np.searchsorted(fr_all, [mid, mid + 10])
    img = np.zeros((H, W), np.int32)
    np.add.at(img, (y_all[i0:i1].astype(np.int64),
                    x_all[i0:i1].astype(np.int64)), 1)
    return dict(rows=rows, per_frame_series={name: (tt, epf)},
                window_series={name: window_series},
                occ_hist={(name,) + k: v for k, v in occ_hist.items()},
                amort={name: amort}, heat={name: pc.astype(np.int32)},
                hot_list={name: np.argwhere(hot)},
                check_imgs={name: (img, mid)}, names=[name])


def wcsv(out, fname, rs):
    if not rs:
        return
    keys = []
    for r in rs:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(os.path.join(out, fname), "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=keys)
        wr.writeheader()
        for r in rs:
            wr.writerow({k: (f"{v:.6g}" if isinstance(v, float) else v)
                         for k, v in r.items()})


def report(out, st):
    os.makedirs(out, exist_ok=True)
    R = st["rows"]
    for fname, k in [("dataset_summary.csv", "dataset"),
                     ("event_rate_summary.csv", "rate"),
                     ("block_occupancy_summary.csv", "occ"),
                     ("locality_summary.csv", "loc"),
                     ("scan_order_summary.csv", "order"),
                     ("polarity_summary.csv", "pol"),
                     ("break_even_summary.csv", "brk"),
                     ("memory_update_summary.csv", "rmw"),
                     ("banking_summary.csv", "bank"),
                     ("hot_pixel_summary.csv", "hot"),
                     ("collision_proxy_summary.csv", "collide")]:
        wcsv(out, fname, R[k])
    names = st["names"]
    for nm in names:
        np.savetxt(os.path.join(out, f"hot_pixel_candidates_{nm}.csv"),
                   st["hot_list"][nm][:, ::-1], fmt="%d", delimiter=",",
                   header="x,y", comments="")

    fig, ax = plt.subplots(len(names), 1, figsize=(10, 2.6 * len(names)),
                           sharex=True)
    ax = np.atleast_1d(ax)
    for a, nm in zip(ax, names):
        tt, epf = st["per_frame_series"][nm]
        a.plot(tt / 1e3, epf / 1e3, lw=0.6)
        a.set_ylabel("k events/frame")
        a.set_title(nm, fontsize=9)
    ax[-1].set_xlabel("time since first frame [ms] (frame period ~0.773 ms)")
    fig.tight_layout()
    fig.savefig(os.path.join(out, "events_per_frame.png"), dpi=120)
    plt.close(fig)

    fig, ax = plt.subplots(1, 3, figsize=(13, 3.4))
    for a, wms in zip(ax, (1, 5, 10)):
        for nm in names:
            b = st["window_series"][nm][wms]
            a.plot(np.arange(b.size) * wms, b * 1000 / wms / 1e6, lw=0.7,
                   label=nm)
        a.set_title(f"{wms} ms windows (frame-granular)")
        a.set_xlabel("time [ms]")
        a.set_ylabel("rate [M events/s]")
    ax[0].legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "events_per_time_window.png"), dpi=120)
    plt.close(fig)

    for (bw, bh) in [(4, 4), (8, 8), (16, 16)]:
        fig, a = plt.subplots(figsize=(7, 3.6))
        for nm in names:
            h = st["occ_hist"][(nm, bw, bh)][1:]
            a.plot(np.arange(1, h.size + 1), h / h.sum(), marker=".", lw=0.8,
                   label=nm)
        a.set_yscale("log")
        a.set_xlabel(f"events in an occupied {bw}x{bh} block (one frame)")
        a.set_ylabel("fraction of occupied blocks")
        a.legend(fontsize=7)
        a.grid(alpha=0.3)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"block_occupancy_{bw}x{bh}.png"),
                    dpi=120)
        plt.close(fig)

    fig, ax = plt.subplots(1, len(names), figsize=(5.2 * len(names), 4))
    ax = np.atleast_1d(ax)
    for a, nm in zip(ax, names):
        im = a.imshow(np.log10(1 + st["heat"][nm]), cmap="magma",
                      aspect="equal")
        a.set_title(f"{nm}: log10(1+events/pixel)", fontsize=9)
        fig.colorbar(im, ax=a, fraction=0.035)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "pixel_event_heatmap.png"), dpi=110)
    plt.close(fig)

    fig, ax = plt.subplots(1, len(names), figsize=(5.2 * len(names), 4))
    ax = np.atleast_1d(ax)
    for a, nm in zip(ax, names):
        img, mid = st["check_imgs"][nm]
        a.imshow(np.minimum(img, 3), cmap="gray_r", aspect="equal")
        a.set_title(f"{nm}: frames {mid}..{mid + 9} (x right, y down)",
                    fontsize=9)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "decode_check_accumulated.png"), dpi=110)
    plt.close(fig)

    fig, a = plt.subplots(figsize=(7, 4))
    labels = [f"{bw}x{bh}" for bw, bh in SHAPES]
    for nm in names:
        a.plot(labels, [st["amort"][nm][s] for s in SHAPES], marker="o",
               label=nm)
    a.axhline(1, color="gray", lw=0.8)
    a.set_ylabel("events / occupied block (per frame)")
    a.set_xlabel("block shape (w x h); 1x8 = native Group-AER group")
    a.set_yscale("log")
    a.legend(fontsize=7)
    a.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "block_amortization_vs_block_size.png"),
                dpi=120)
    plt.close(fig)


def merge_states(states):
    keys = ("per_frame_series", "window_series", "occ_hist", "amort",
            "heat", "check_imgs", "hot_list")
    st = {"rows": {k: [] for k in states[0]["rows"]}, "names": []}
    for k in keys:
        st[k] = {}
    for s_ in states:
        for k, v in s_["rows"].items():
            st["rows"][k].extend(v)
        for k in keys:
            st[k].update(s_[k])
        st["names"].extend(s_["names"])
    return st


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "one":
        name, path = sys.argv[3].split("=", 1)
        st = analyze_one(name, path)
        with open(sys.argv[2], "wb") as f:
            pickle.dump(st, f)
    elif mode == "merge":
        states = []
        for pth in sys.argv[3:]:
            with open(pth, "rb") as f:
                states.append(pickle.load(f))
        report(sys.argv[2], merge_states(states))
    else:
        sys.exit("usage: one <state.pkl> name=npz | merge <out_dir> pkl...")
