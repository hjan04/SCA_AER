#!/usr/bin/env python3
"""Build a golden system-test scenario for the largest available decoded frame."""
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "verification/system"))
from gen_system_vectors import Scenario, load_codex

CODEX = ROOT / "codex"
npz_path = ROOT / "reference/real_traffic/sept22b_f900_f901.npz"
out = Path(__file__).resolve().parent / "peak_frame/scenario"
CameraConfig, FixedT32Mapper, make_grid, ray2addr, Pose = load_codex(CODEX)
cfg = CameraConfig(fx=800, fy=800)
d = np.load(npz_path)
frame = 901
frames, times, xs, ys, polarities, native_words, slots = (
    d[k] for k in ("frame", "t_us", "x", "y", "p", "word", "slot"))
ix = np.flatnonzero(frames == frame)
sc = Scenario("peak_frame_901", cfg, (CameraConfig, FixedT32Mapper, make_grid, ray2addr, Pose))
# Match the existing real-data system-test convention: frame 900 uses identity;
# frame 901 uses synthetic yaw=5 degrees and roll=3 degrees. This is not pose GT.
sc.add_frame(0, yaw=5, roll=3)
cur = None
for j in ix:
    key = int(native_words[j])
    if cur is None or cur["key"] != key:
        if cur is not None:
            sc.add_word(0, cur["x"], cur["ga"], cur["gb"])
        cur = dict(key=key, x=int(xs[j]), ga=None, gb=None)
    slot = "ga" if int(slots[j]) == 0 else "gb"
    group, bit = int(ys[j]) >> 3, int(ys[j]) & 7
    if cur[slot] is None:
        cur[slot] = [group, 0, int(polarities[j])]
    cur[slot][1] |= 1 << bit
if cur is not None:
    sc.add_word(0, cur["x"], cur["ga"], cur["gb"])
scenario_dir = out.parent / sc.name
scenario_dir.mkdir(parents=True, exist_ok=True)
with (scenario_dir / "frames.txt").open("w") as f:
    f.write("0 0\n")
with (scenario_dir / "grids.hex").open("w") as f:
    for gy in range(24):
        for gx in range(31):
            x, y, z = (int(v) & 0xffff for v in sc.grids[0].nodes[gy, gx])
            f.write(f"{(x << 32) | (y << 16) | z:012x}\n")
with (scenario_dir / "words.hex").open("w") as f:
    for w in sc.words:
        v = (w["frame"] & 0xff) << 44 | (w["x"] & 0x3ff) << 34
        if w["ga"] is not None:
            grp, mask, pol = w["ga"]
            v |= 1 << 33 | (grp & 0x7f) << 26 | (mask & 0xff) << 18 | (pol & 1) << 17
        if w["gb"] is not None:
            grp, mask, pol = w["gb"]
            v |= 1 << 16 | (grp & 0x7f) << 9 | (mask & 0xff) << 1 | (pol & 1)
        f.write(f"{v:013x}\n")
events = sum(sum(bin(int(g[1])).count("1") for g in (w["ga"], w["gb"]) if g is not None)
               for w in sc.words)
issues = sum((sum(bin(int(g[1])).count("1") for g in (w["ga"], w["gb"]) if g is not None)+1)//2
             for w in sc.words)
(scenario_dir / "expect.txt").write_text(
    f"words={len(sc.words)}\nevents={events}\ndropped=0\nelite_records=0\n"
    f"elite_merged=0\nd2_records=0\nsat_loss=-1\nissue_cycles={issues}\nframes=1\n")
expect = {"words": len(sc.words), "events": events, "issue_cycles": issues}
src_hash = __import__("hashlib").sha256(npz_path.read_bytes()).hexdigest()
(scenario_dir / "provenance.txt").write_text(
    f"source={npz_path}\nsha256={src_hash}\nframe={frame}\n"
    f"event_count={len(ix)}\nnative_words={len(sc.words)}\n"
    "pose_convention=synthetic yaw=5deg, pitch=0deg, roll=3deg; matches existing system-test frame-901 convention; not real pose ground truth\n"
    "ordering=stable source order; native words grouped by recorded word id; group A then group B slots retained; polarity preserved\n"
)
print(expect)
print(f"source_sha256={src_hash}")
