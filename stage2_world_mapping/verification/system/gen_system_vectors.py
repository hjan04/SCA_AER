#!/usr/bin/env python3
"""Generate system-level stimulus + expected results for tb_system.sv.

Golden models are Codex's frozen software references, imported READ-ONLY from
the Codex worktree (CODEX_DIR):
  make_fixed_t32_grid, FixedT32Mapper.map_event  -> Q1.15 ray per event
  ray_q15_to_world_address                         -> world address
The control-side reference implemented here:
  issue order (group A bits LSB->MSB, then group B), invalid-coordinate drop,
  tile/bank/word address (Exp05b), packed ON/OFF saturating accumulation,
  consecutive-only native-group E-lite merge count (Exp05b semantics).

Each scenario directory receives:
  frames.txt      one line per grid load: "<epoch> <partial_nodes>"
  grids.hex       744 lines (48-bit {x,y,z}) per grid load, gy-major
  words.hex       52-bit native words (wm_ctrl_pkg::nword_t packing)
  exp_events.hex  per issued event: {world_addr[14:0], x[9:0], y[9:0]}
  exp_mem.hex     2048 x 128-bit tile words, index = bank*512 + word
  expect.txt      key=value expected counters
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

import numpy as np

import os

STAGE2 = Path(__file__).resolve().parents[2]
# Path resolution only (no behavioural effect): prefer the canonical in-tree
# model; external fallback is for older development checkouts only.
_CODEX_FALLBACK = Path("/tmp/sca_aer_codex_modeling2/stage2_world_mapping/codex")
CODEX_DIR = Path(os.environ.get("WM_CODEX_DIR") or
                 (STAGE2 / "codex" if (STAGE2 / "codex/model/fixed_point.py").exists()
                  else _CODEX_FALLBACK))
_REAL_CANDIDATES = [
    Path(os.environ["WM_REAL_SUBSET"]) if os.environ.get("WM_REAL_SUBSET") else None,
    STAGE2 / "reference/real_traffic/sept22b_f900_f901.npz",
    STAGE2 / "claude/verification_plan/exp03_cache/sept22b_1642_44.npz",
]


def load_codex(codex_dir: Path):
    sys.path.insert(0, str(codex_dir))
    from model.common import CameraConfig
    from model.fixed_point import FixedT32Mapper, make_fixed_t32_grid
    from model.ray_address import ray_q15_to_world_address
    from experiments.exp02_architecture_tournament.candidate_models import Pose
    return CameraConfig, FixedT32Mapper, make_fixed_t32_grid, ray_q15_to_world_address, Pose


W, H = 960, 720
MAXC = 15


class Scenario:
    def __init__(self, name, cfg, codex):
        self.name = name
        self.cfg = cfg
        (self.CameraConfig, self.FixedT32Mapper, self.make_grid,
         self.ray2addr, self.Pose) = codex
        self.grid_loads = []        # (epoch, partial_nodes, grid)
        self.grids = {}             # epoch -> grid
        self.words = []             # dicts
        self.notes = {}

    def add_frame(self, epoch, yaw=0.0, pitch=0.0, roll=0.0, partial=0, grid=None):
        if grid is None:
            grid = self.make_grid(self.cfg, self.Pose(math.radians(yaw), math.radians(pitch),
                                                      math.radians(roll)), 15, 16)
        self.grids[epoch] = grid
        self.grid_loads.append((epoch, partial, grid))

    def add_word(self, frame, x, ga=None, gb=None):
        """ga/gb = (group, mask, pol) or None."""
        self.words.append(dict(frame=frame, x=x, ga=ga, gb=gb))

    # ------------------------------------------------------------- reference
    def run_reference(self):
        events = []           # (frame, word_seq, slot, x, y, pol)
        dropped = 0
        for seq, w in enumerate(self.words):
            for slot, g in ((0, w["ga"]), (1, w["gb"])):
                if g is None:
                    continue
                grp, mask, pol = g
                for k in range(8):
                    if mask >> k & 1:
                        y = grp * 8 + k
                        if w["x"] < W and y < H:
                            events.append((w["frame"], seq, slot, w["x"], y, pol))
                        else:
                            dropped += 1
        mappers = {e: self.FixedT32Mapper(g, self.cfg) for e, g in self.grids.items()}
        mapped = []
        for (fr, seq, slot, x, y, pol) in events:
            q = mappers[fr].map_event(x, y).ray_q
            a = self.ray2addr(*map(int, q)).world_addr
            wx, wy = a & 0xFF, a >> 8
            tx, ty = wx >> 2, wy >> 2
            bank = (tx & 3) ^ ((-ty) & 3)
            waddr = (ty << 4) | (tx >> 2)
            cell = ((wy & 3) << 2) | (wx & 3)
            mapped.append((fr, seq, slot, x, y, pol, a, bank, waddr, cell))
        # memory: final cell = min(15, count) per plane (monotone saturating add)
        cnt = np.zeros((4, 512, 16, 2), dtype=np.int64)
        for m in mapped:
            cnt[m[7], m[8], m[9], 0 if m[5] else 1] += 1
        sat_loss = int(np.maximum(cnt - MAXC, 0).sum())
        mem = np.minimum(cnt, MAXC)
        # consecutive-only E-lite records (+ diagnostics: same-cell folds,
        # multi-cell records)
        recs = merged = same_cell = multi_cell = 0
        prev = None
        cells = {}
        def close(c):
            nonlocal merged, same_cell, multi_cell
            n = sum(c.values())
            if n >= 2:
                merged += 1
            if any(v >= 2 for v in c.values()):
                same_cell += 1
            if len(c) >= 2:
                multi_cell += 1
        for m in mapped:
            key = (m[0], m[1], m[2], m[7], m[8])
            if key != prev:
                if prev is not None:
                    close(cells)
                recs += 1
                prev = key
                cells = {}
            cells[m[9]] = cells.get(m[9], 0) + 1
        if prev is not None:
            close(cells)
        self.mapped = mapped
        self.mem = mem
        self.expect = dict(
            words=len(self.words), events=len(mapped), dropped=dropped,
            elite_records=recs, elite_merged=merged, d2_records=len(mapped),
            sat_loss=sat_loss,
            issue_cycles=sum((n + 1) // 2 for n in self._events_per_word()),
            frames=len(self.grid_loads),
            elite_same_cell_records=same_cell, elite_multi_cell_records=multi_cell)

    def _events_per_word(self):
        out = []
        for w in self.words:
            n = 0
            for g in (w["ga"], w["gb"]):
                if g is None:
                    continue
                grp, mask, _ = g
                n += sum(1 for k in range(8) if mask >> k & 1 and w["x"] < W and grp * 8 + k < H)
            out.append(n)
        return out

    # ------------------------------------------------------------- writers
    def write(self, root: Path):
        d = root / self.name
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "frames.txt", "w") as f:
            for epoch, partial, _ in self.grid_loads:
                f.write(f"{epoch} {partial}\n")
        with open(d / "grids.hex", "w") as f:
            for _, _, g in self.grid_loads:
                for gy in range(24):
                    for gx in range(31):
                        x, y, z = (int(v) & 0xFFFF for v in g.nodes[gy, gx])
                        f.write(f"{(x << 32) | (y << 16) | z:012x}\n")
        with open(d / "words.hex", "w") as f:
            for w in self.words:
                v = (w["frame"] & 0xFF) << 44 | (w["x"] & 0x3FF) << 34
                if w["ga"] is not None:
                    grp, mask, pol = w["ga"]
                    v |= 1 << 33 | (grp & 0x7F) << 26 | (mask & 0xFF) << 18 | (pol & 1) << 17
                if w["gb"] is not None:
                    grp, mask, pol = w["gb"]
                    v |= 1 << 16 | (grp & 0x7F) << 9 | (mask & 0xFF) << 1 | (pol & 1)
                f.write(f"{v:013x}\n")
        with open(d / "exp_events.hex", "w") as f:
            for m in self.mapped:
                f.write(f"{(m[6] << 20) | (m[3] << 10) | m[4]:09x}\n")
        with open(d / "exp_mem.hex", "w") as f:
            for b in range(4):
                for wd in range(512):
                    v = 0
                    for c in range(16):
                        on, off = int(self.mem[b, wd, c, 0]), int(self.mem[b, wd, c, 1])
                        v |= ((on << 4) | off) << (8 * c)
                    f.write(f"{v:032x}\n")
        with open(d / "expect.txt", "w") as f:
            for k, v in self.expect.items():
                f.write(f"{k}={v}\n")
        return self.expect


# ----------------------------------------------------------------- scenarios
def rng_words(sc, rng, frame, n, max_events=16):
    for _ in range(n):
        x = int(rng.integers(0, W))
        ga = (int(rng.integers(0, 90)), int(rng.integers(1, 256)), int(rng.integers(0, 2)))
        gb = None
        if rng.random() < 0.85:
            gb = (int(rng.integers(0, 90)), int(rng.integers(1, 256)), int(rng.integers(0, 2)))
        sc.add_word(frame, x, ga, gb)


def column_sweep(sc, frame, x0, ncols, rng, density=0.35):
    """Column-major, real-sensor-like words: per column, a few groups."""
    for x in range(x0, x0 + ncols):
        groups = sorted(rng.choice(90, size=int(rng.integers(1, 6)), replace=False))
        i = 0
        while i < len(groups):
            ga_g = int(groups[i])
            ga = (ga_g, int(rng.integers(1, 256)) | 1, int(rng.integers(0, 2)))
            gb = None
            if i + 1 < len(groups):
                gb = (int(groups[i + 1]), int(rng.integers(1, 256)), int(rng.integers(0, 2)))
            sc.add_word(frame, x, ga, gb)
            i += 2


def build_scenarios(codex, out: Path, quick=False):
    CameraConfig = codex[0]
    cfg = CameraConfig(fx=800, fy=800)
    rng = np.random.default_rng(20261008)
    scs = []

    s = Scenario("s01_one_word", cfg, codex)
    s.add_frame(0)
    s.add_word(0, 480, (45, 0b10110101, 1), (46, 0b10000001, 0))
    scs.append(s)

    s = Scenario("s02_one_event", cfg, codex)
    s.add_frame(0)
    s.add_word(0, 100, (10, 0b00001000, 1), None)
    scs.append(s)

    s = Scenario("s03_odd_counts", cfg, codex)
    s.add_frame(0, yaw=10)
    for n, x in ((1, 5), (3, 200), (5, 400), (7, 600), (9, 800), (15, 959)):
        mask = (1 << n) - 1
        ga = (20, mask & 0xFF, 1)
        gb = (21, (mask >> 8) & 0xFF, 0) if n > 8 else None
        s.add_word(0, x, ga, gb)
    scs.append(s)

    s = Scenario("s04_two_lane_dispatch", cfg, codex)
    s.add_frame(0, yaw=-20, pitch=5)
    for n in (2, 4, 6, 8, 16, 2, 1, 16):
        mask = (1 << n) - 1
        s.add_word(0, int(rng.integers(0, W)), (30, mask & 0xFF, 1),
                   (60, (mask >> 8) & 0xFF, 0) if n > 8 else None)
    rng_words(s, rng, 0, 200)
    scs.append(s)

    s = Scenario("s05_dense_merge_banks", cfg, codex)   # merges, bank conflicts, RAW
    s.add_frame(0, roll=12)
    column_sweep(s, 0, 300, 120, rng)
    scs.append(s)

    s = Scenario("s06_saturation_on_off", cfg, codex)
    s.add_frame(0)
    for _ in range(3):                                  # 3 x 8 same-cell events
        s.add_word(0, 480, (45, 0xFF, 1), (46, 0xFF, 0))
    for _ in range(3):
        s.add_word(0, 120, (10, 0xFF, 0), None)
    scs.append(s)

    s = Scenario("s07_frame_grid_swap", cfg, codex)
    for f, (yw, pt, rl) in enumerate(((0, 0, 0), (15, 0, 0), (30, -5, 8), (45, 10, -12), (60, 0, 25))):
        s.add_frame(f, yw, pt, rl)
        column_sweep(s, f, 100 + 150 * f, 40, rng)
    scs.append(s)

    s = Scenario("s08_partial_grid", cfg, codex)
    s.add_frame(0)
    s.add_frame(1, yaw=30, partial=500)                 # loader first sends 500 nodes
    s.add_frame(2, yaw=60)
    for f in range(3):
        column_sweep(s, f, 200, 30, rng)
    scs.append(s)

    s = Scenario("s09_invalid_coords", cfg, codex)
    s.add_frame(0)
    s.add_word(0, 959, (89, 0xFF, 1), None)             # y 712..719 valid
    s.add_word(0, 960, (10, 0x0F, 1), None)             # x invalid -> 4 dropped
    s.add_word(0, 50, (90, 0x03, 0), (95, 0x01, 1))     # y >= 720 -> 3 dropped
    s.add_word(0, 51, (5, 0x01, 0), None)
    scs.append(s)

    # Codex numeric vectors through the integrated top (subset)
    s = Scenario("s10_codex_vectors", cfg, codex)
    poses = {0: (0, 0, 0), 1: (40, 0, 0), 2: (-40, 0, 0), 3: (25, -15, 12)}
    rows = list(csv.DictReader(open(CODEX_DIR / "results/exp05/rtl_vectors.csv")))
    smoke = {r["vector_id"] for r in csv.DictReader(open(CODEX_DIR / "results/exp05/rtl_smoke_vectors.csv"))}
    pick = [r for r in rows if r["vector_id"] in smoke]
    pick += [rows[i] for i in rng.choice(len(rows), size=(120 if quick else 600), replace=False)]
    for pid, (yw, pt, rl) in poses.items():
        s.add_frame(pid, yw, pt, rl)
        for r in pick:
            if int(r["pose_id"]) == pid:
                x, y = int(r["x"]), int(r["y"])
                s.add_word(pid, x, (y >> 3, 1 << (y & 7), int(rng.integers(0, 2))), None)
    s.notes["codex_rows"] = len(pick)
    scs.append(s)

    # Real traffic subset (decoded Sept22b, Exp03 cache) with synthetic poses
    npz = next((c for c in _REAL_CANDIDATES if c is not None and c.exists()), None)
    if npz is not None:
        d = np.load(npz)
        fr, x, y, p, w, sl = d["frame"], d["x"], d["y"], d["p"], d["word"], d["slot"]
        s = Scenario("s11_real_sept22b", cfg, codex)
        nfr = 1 if quick else 2
        f0 = 900
        for k in range(nfr):
            i0, i1 = np.searchsorted(fr, [f0 + k, f0 + k + 1])
            lim = i0 + (4000 if quick else 20000)
            i1 = min(i1, lim)
            s.add_frame(k, yaw=5 * k, roll=3 * k)
            # rebuild native words (word, slot) -> masks, preserving stream order
            cur = None
            for j in range(i0, i1):
                key = int(w[j])
                g = int(y[j]) >> 3
                bit = int(y[j]) & 7
                if cur is None or cur["key"] != key:
                    if cur is not None:
                        s.add_word(k, cur["x"], cur["ga"], cur["gb"])
                    cur = dict(key=key, x=int(x[j]), ga=None, gb=None)
                slot = "ga" if int(sl[j]) == 0 else "gb"
                if cur[slot] is None:
                    cur[slot] = [g, 0, int(p[j])]
                cur[slot][1] |= 1 << bit
            if cur is not None:
                s.add_word(k, cur["x"], cur["ga"] and tuple(cur["ga"]), cur["gb"] and tuple(cur["gb"]))
        # convert any list groups to tuples
        for wd in s.words:
            for sk in ("ga", "gb"):
                if isinstance(wd[sk], list):
                    wd[sk] = tuple(wd[sk])
        scs.append(s)

    results = {}
    for sc in scs:
        sc.run_reference()
        results[sc.name] = sc.write(out)
        print(sc.name, results[sc.name], flush=True)
    return results


def check_grid_order(codex):
    """Verify gy-major node order against Codex's grid_test_image.csv."""
    CameraConfig, _, make_grid, _, Pose = codex
    rows = list(csv.DictReader(open(CODEX_DIR / "results/exp05b/grid_test_image.csv")))
    g = make_grid(CameraConfig(fx=800, fy=800),
                  Pose(math.radians(20), math.radians(-10), math.radians(15)), 15, 16)
    bad = 0
    for r in rows:
        idx, gx, gy = int(r["node_idx"]), int(r["gx"]), int(r["gy"])
        if idx != gy * 31 + gx:
            bad += 1
        if tuple(int(v) for v in g.nodes[gy, gx]) != (int(r["ray_x_q15"]), int(r["ray_y_q15"]), int(r["ray_z_q15"])):
            bad += 1
    print(f"grid_test_image.csv: {len(rows)} nodes, mismatches={bad}")
    return bad


def main():
    global CODEX_DIR
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--codex-dir", type=Path, default=CODEX_DIR)
    a = ap.parse_args()
    CODEX_DIR = a.codex_dir
    codex = load_codex(a.codex_dir)
    bad = check_grid_order(codex)
    build_scenarios(codex, a.out, a.quick)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
