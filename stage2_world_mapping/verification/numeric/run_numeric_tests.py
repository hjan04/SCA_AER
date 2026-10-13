#!/usr/bin/env python3
"""Generate Exp05/05b stimulus and run self-checking Icarus testbenches."""
from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
STAGE2 = HERE.parents[1]
CODEX = STAGE2 / "codex"
sys.path.insert(0, str(CODEX))

from model.common import CameraConfig
from model.fixed_point import FixedT32Mapper, make_fixed_t32_grid
from model.ray_address import ray_q15_to_world_address
from experiments.exp02_architecture_tournament.candidate_models import Pose


RTL = STAGE2 / "rtl"
PKG = RTL / "include/wm_pkg.sv"
NUMERIC = RTL / "numeric"
RTL_SOURCES = [
    PKG,
    NUMERIC / "wm_lerp.sv",
    NUMERIC / "wm_isqrt.sv",
    NUMERIC / "wm_cordic_vectoring.sv",
    NUMERIC / "wm_ray2angle.sv",
    NUMERIC / "wm_world_quant.sv",
    NUMERIC / "wm_mapper_lane.sv",
]


def pack_ray(x: int, y: int, z: int) -> int:
    return ((x & 0xFFFF) << 32) | ((y & 0xFFFF) << 16) | (z & 0xFFFF)


def write_mem(path: Path, values: list[int], bits: int) -> None:
    digits = (bits + 3) // 4
    mask = (1 << bits) - 1
    with path.open("w", encoding="ascii") as stream:
        for value in values:
            stream.write(f"{value & mask:0{digits}x}\n")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def generate_vectors(build: Path) -> tuple[int, int, int, int]:
    exp05 = CODEX / "results/exp05/rtl_vectors.csv"
    exp05b = CODEX / "results/exp05b/rtl_address_vectors.csv"
    lane_rows = read_csv(exp05)
    addr_rows = read_csv(exp05b)
    lane_smoke = read_csv(CODEX / "results/exp05/rtl_smoke_vectors.csv")
    addr_smoke = read_csv(CODEX / "results/exp05b/rtl_address_smoke_vectors.csv")
    lane_ids = {row["vector_id"] for row in lane_rows}
    addr_ids = {row["vector_id"] for row in addr_rows}
    if any(row["vector_id"] not in lane_ids for row in lane_smoke):
        raise RuntimeError("Exp05 smoke vector is missing from the full interpolation dataset")
    if any(row["vector_id"] not in addr_ids for row in addr_smoke):
        raise RuntimeError("Exp05b smoke vector is missing from the full address dataset")
    cfg = CameraConfig(fx=800, fy=800)
    poses = {
        0: Pose(0.0),
        1: Pose(math.radians(40.0)),
        2: Pose(math.radians(-40.0)),
        3: Pose(math.radians(25.0), math.radians(-15.0), math.radians(12.0)),
    }
    grids = {pid: make_fixed_t32_grid(cfg, pose, 15, 16) for pid, pose in poses.items()}
    lane_mem: list[int] = []
    for row in lane_rows:
        pid = int(row["pose_id"])
        grid = grids[pid]
        ix, iy = int(row["grid_ix"]), int(row["grid_iy"])
        ox, oy = int(row["frac_x_num"]), int(row["frac_y_num"])
        n00 = pack_ray(*map(int, grid.nodes[iy, ix]))
        n10 = pack_ray(*map(int, grid.nodes[iy, ix + 1]))
        n01 = pack_ray(*map(int, grid.nodes[iy + 1, ix]))
        n11 = pack_ray(*map(int, grid.nodes[iy + 1, ix + 1]))
        q = tuple(int(row[k]) for k in ("ray_x_q", "ray_y_q", "ray_z_q"))
        ref = FixedT32Mapper(grid, cfg).map_event(int(row["x"]), int(row["y"]))
        if tuple(ref.ray_q) != q:
            raise RuntimeError(f"Exp05 vector {row['vector_id']} failed reference reconstruction")
        addr = ray_q15_to_world_address(*q).world_addr
        # low-to-high: yoff, xoff, node00/10/01/11, expected Q ray, world address
        value = oy | (ox << 5) | (n00 << 10) | (n10 << 58) | (n01 << 106) | (n11 << 154)
        value |= pack_ray(*q) << 202
        value |= addr << 250
        lane_mem.append(value)
    write_mem(build / "lane_vectors.hex", lane_mem, 265)

    address_mem: list[int] = []
    cordic_mem: list[int] = []
    sqrt_mem: list[int] = []
    for row in addr_rows:
        x, y, z = (int(row[k]) for k in ("ray_x_q15", "ray_y_q15", "ray_z_q15"))
        az, el, addr = (int(row[k]) for k in ("az_bam32", "el_bam32", "expected_world_addr"))
        address_mem.append(pack_ray(x, y, z) | ((az & 0xFFFFFFFF) << 48) |
                           ((el & 0xFFFFFFFF) << 80) | (addr << 112))

        radicand = (x*x + z*z) << 24
        root = math.isqrt(radicand)
        sqrt_mem.append(radicand | (root << 56))

        # Standalone CORDIC vectors: azimuth atan2(ray_x,ray_z), then
        # elevation atan2(ray_y,isqrt(ray_x^2+ray_z^2)), with 12 guard bits.
        inputs = ((z << 12, x << 12, az), (root, y << 12, el))
        for xin, yin, expected in inputs:
            cordic_mem.append((xin & 0xFFFFFFFF) | ((yin & 0xFFFFFFFF) << 32) |
                              ((expected & 0xFFFFFFFF) << 64))
    write_mem(build / "address_vectors.hex", address_mem, 127)
    write_mem(build / "cordic_vectors.hex", cordic_mem, 96)
    write_mem(build / "isqrt_vectors.hex", sqrt_mem, 84)
    return len(lane_rows), len(addr_rows), len(cordic_mem), len(sqrt_mem), len(lane_smoke), len(addr_smoke)


def compile_and_run(top: str, tb: str, build: Path) -> None:
    sim = build / f"{top}.vvp"
    cmd = ["iverilog", "-g2012", "-s", top, "-o", str(sim),
           *map(str, RTL_SOURCES), str(HERE / tb)]
    subprocess.run(cmd, cwd=build, check=True)
    subprocess.run(["vvp", str(sim)], cwd=build, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", type=Path,
                        help="retain generated input vectors and simulations here")
    args = parser.parse_args()
    temp = None
    if args.build_dir:
        build = args.build_dir.resolve()
        build.mkdir(parents=True, exist_ok=True)
    else:
        temp = tempfile.TemporaryDirectory(prefix="wm_numeric_")
        build = Path(temp.name)

    counts = generate_vectors(build)
    print(f"Generated inputs: Exp05 interpolation={counts[0]} (smoke included={counts[4]}), "
          f"Exp05b rays={counts[1]} (smoke included={counts[5]}), "
          f"standalone CORDIC={counts[2]}, integer sqrt={counts[3]}", flush=True)
    compile_and_run("tb_mapper_lane", "tb_mapper_lane.sv", build)
    compile_and_run("tb_isqrt", "tb_isqrt.sv", build)
    compile_and_run("tb_cordic", "tb_cordic.sv", build)
    compile_and_run("tb_ray2angle", "tb_ray2angle.sv", build)
    if temp:
        temp.cleanup()
    print("All numeric RTL regressions passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
