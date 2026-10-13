"""Bit-accurate integer model for the V1 T32 world-ray interpolator.

Pose/grid generation is deliberately outside the event datapath.  This module
consumes an already quantized grid and models per-event interpolation exactly.
The final atan2/world-bin conversion is a software oracle until the RTL angle
quantizer is specified independently.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Iterable

import numpy as np

from model.common import CameraConfig, ray_to_angles, angles_to_world_pixel


def round_shift(value: int, shift: int, mode: str = "nearest_even") -> int:
    """Divide by 2**shift, using truncation-to-zero or signed nearest-even."""
    if shift < 0:
        raise ValueError("shift must be nonnegative")
    if mode == "truncate_zero":
        den = 1 << shift
        return (abs(value) // den) * (-1 if value < 0 else 1)
    if mode != "nearest_even":
        raise ValueError(f"unsupported rounding mode {mode!r}")
    den = 1 << shift
    sign = -1 if value < 0 else 1
    q, r = divmod(abs(value), den)
    half = den >> 1
    if r > half or (r == half and q & 1):
        q += 1
    return sign * q


def signed_bounds(bits: int) -> tuple[int, int]:
    if bits < 2:
        raise ValueError("signed format needs at least 2 bits")
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def saturate_signed(value: int, bits: int) -> int:
    lo, hi = signed_bounds(bits)
    return min(hi, max(lo, int(value)))


def quantize_q(value: float, frac_bits: int, total_bits: int, rounding="nearest_even") -> int:
    scale = 1 << frac_bits
    scaled = value * scale
    if rounding == "nearest_even":
        q = int(round(scaled))
    elif rounding == "truncate_zero":
        q = math.trunc(scaled)
    else:
        raise ValueError(f"unsupported rounding mode {rounding!r}")
    return saturate_signed(q, total_bits)


@dataclass(frozen=True)
class FixedGrid:
    nodes: np.ndarray  # [ny,nx,3], signed integer Q1.F values
    frac_bits: int
    total_bits: int
    spacing: int = 32
    sensor_w: int = 960
    sensor_h: int = 720

    @classmethod
    def from_float_nodes(cls, nodes: np.ndarray, frac_bits: int, total_bits: int,
                         spacing=32, sensor_w=960, sensor_h=720,
                         rounding="nearest_even") -> "FixedGrid":
        q = np.empty(nodes.shape, dtype=np.int64)
        for idx in np.ndindex(nodes.shape):
            q[idx] = quantize_q(float(nodes[idx]), frac_bits, total_bits, rounding)
        return cls(q, frac_bits, total_bits, spacing, sensor_w, sensor_h)

    @property
    def nx(self):
        return int(self.nodes.shape[1])

    @property
    def ny(self):
        return int(self.nodes.shape[0])


@dataclass(frozen=True)
class MapResult:
    ray_q: tuple[int, int, int]
    ray: tuple[float, float, float]
    world_x: int
    world_y: int
    world_addr: int
    grid_ix: int
    grid_iy: int
    frac_x: int
    frac_y: int


class FixedT32Mapper:
    """RTL-callable event API over a preloaded fixed-point T32 grid."""
    def __init__(self, grid: FixedGrid, config: CameraConfig,
                 rounding: str = "nearest_even", output_frac_bits: int | None = None):
        if grid.spacing != 32:
            raise ValueError("V1 fixed mapper requires T32")
        self.grid, self.config, self.rounding = grid, config, rounding
        self.output_frac_bits = grid.frac_bits if output_frac_bits is None else output_frac_bits
        if self.output_frac_bits != grid.frac_bits:
            raise ValueError("this RTL reference currently keeps node/output Q format equal")

    def map_event(self, x: int, y: int) -> MapResult:
        g = self.grid
        if not (0 <= int(x) < g.sensor_w and 0 <= int(y) < g.sensor_h):
            raise ValueError(f"invalid pixel coordinate ({x},{y})")
        ix, iy = int(x) // 32, int(y) // 32
        ox, oy = int(x) & 31, int(y) & 31
        q00 = g.nodes[iy, ix].astype(object)
        q10 = g.nodes[iy, ix + 1].astype(object)
        q01 = g.nodes[iy + 1, ix].astype(object)
        q11 = g.nodes[iy + 1, ix + 1].astype(object)
        # Difference form: each component uses signed (W+1) delta, then
        # signed delta*5-bit offset; /32 is an arithmetic shift with stated rounding.
        top = [int(q00[c]) + round_shift((int(q10[c])-int(q00[c]))*ox, 5, self.rounding)
               for c in range(3)]
        bottom = [int(q01[c]) + round_shift((int(q11[c])-int(q01[c]))*ox, 5, self.rounding)
                  for c in range(3)]
        out = [saturate_signed(top[c] + round_shift((bottom[c]-top[c])*oy, 5, self.rounding),
                               g.total_bits) for c in range(3)]
        ray = tuple(v / float(1 << g.frac_bits) for v in out)
        angles = ray_to_angles(ray)
        wx, wy = angles_to_world_pixel(*angles, self.config)
        return MapResult(tuple(out), ray, wx, wy, wy*self.config.world_w+wx,
                         ix, iy, ox, oy)

    def map_native_group(self, events: Iterable[tuple[int, int]]) -> list[MapResult]:
        """Map Exp04 native 1x8 groups with shared horizontal intermediates.

        Events must have a common x and lie in a common y//8 subgroup. These
        constraints ensure every event uses the same horizontal offset and the
        same pair of T32 y-node rows. Each event retains its own vertical lerp.
        """
        events=list(events)
        if not events:
            return []
        if len({x for x,_ in events}) != 1 or len({y//8 for _,y in events}) != 1:
            raise ValueError("native reuse group must share x and y//8")
        x=events[0][0]
        if not (0 <= x < self.grid.sensor_w):
            raise ValueError("invalid pixel coordinate")
        ix=x//32; iy=(events[0][1]//8)//4
        ox=x&31; nodes=self.grid.nodes
        top=[int(nodes[iy,ix,c])+round_shift((int(nodes[iy,ix+1,c])-int(nodes[iy,ix,c]))*ox,5,self.rounding) for c in range(3)]
        bot=[int(nodes[iy+1,ix,c])+round_shift((int(nodes[iy+1,ix+1,c])-int(nodes[iy+1,ix,c]))*ox,5,self.rounding) for c in range(3)]
        out=[]
        for _,y in events:
            if not (0 <= y < self.grid.sensor_h):
                raise ValueError("invalid pixel coordinate")
            oy=y&31
            q=tuple(saturate_signed(top[c]+round_shift((bot[c]-top[c])*oy,5,self.rounding),self.grid.total_bits) for c in range(3))
            ray=tuple(v/float(1<<self.grid.frac_bits) for v in q)
            wx,wy=angles_to_world_pixel(*ray_to_angles(ray),self.config)
            out.append(MapResult(q,ray,wx,wy,wy*self.config.world_w+wx,ix,iy,ox,oy))
        return out

    def map_events(self, xs: Iterable[int], ys: Iterable[int]):
        return [self.map_event(int(x), int(y)) for x, y in zip(xs, ys)]


def float_bilinear(grid: FixedGrid, x: int, y: int) -> tuple[float, float, float]:
    """Floating interpolation using precisely the same quantized node integers."""
    ix, iy = int(x)//32, int(y)//32
    tx, ty = (int(x)&31)/32.0, (int(y)&31)/32.0
    scale = float(1 << grid.frac_bits)
    a, b = grid.nodes[iy, ix]/scale, grid.nodes[iy, ix+1]/scale
    c, d = grid.nodes[iy+1, ix]/scale, grid.nodes[iy+1, ix+1]/scale
    top, bot = (1-tx)*a+tx*b, (1-tx)*c+tx*d
    out = (1-ty)*top+ty*bot
    return tuple(float(v) for v in out)


def merge_group_updates(events, threshold: int = 2, polarity_mode: str = "unsigned_count",
                        world_w: int = 256, tile_cells: int = 4):
    """Return deterministic native-group word writes.

    Each event is (world_addr, polarity, signed_delta). A physical-word proxy
    is the Exp04 row-major tile (`tile_cells` x `tile_cells` world cells).
    If a tile/plane has at least `threshold` events, it emits one masked write
    carrying per-cell deltas; otherwise each event remains an individual write.
    This preserves distinct-cell values while permitting packed-word RMW merge.
    """
    if threshold < 2:
        raise ValueError("merge threshold must be >=2")
    if polarity_mode not in {"unsigned_count","signed_count","separate_on_off"}:
        raise ValueError("invalid accumulator mode")
    if world_w <= 0 or tile_cells <= 0:
        raise ValueError("world width and tile size must be positive")
    nx=(world_w+tile_cells-1)//tile_cells
    buckets={}
    for addr,pol,delta in events:
        addr=int(addr); x=addr%world_w; y=addr//world_w
        word=(y//tile_cells)*nx+(x//tile_cells)
        key=(word,int(pol)) if polarity_mode=="separate_on_off" else word
        cell=(y%tile_cells)*tile_cells+(x%tile_cells)
        buckets.setdefault(key,[]).append((addr,cell,int(delta)))
    requests=[]
    for key in sorted(buckets,key=repr):
        entries=buckets[key]
        if len(entries)>=threshold:
            payload={}
            for addr,cell,delta in entries:
                payload[cell]=payload.get(cell,0)+delta
            requests.append((key,payload,len(entries)))
        else:
            requests.extend((key,{cell:delta},1) for _,cell,delta in entries)
    return requests


def make_float_t32_nodes(config: CameraConfig, pose, spacing=32):
    """Build the same normalized rotated-ray nodes used by Exp02 WarpGrid."""
    import sys
    from pathlib import Path
    codex = Path(__file__).resolve().parents[1]
    if str(codex) not in sys.path:
        sys.path.insert(0, str(codex))
    from experiments.exp02_architecture_tournament.candidate_models import WarpGrid
    return WarpGrid(config, pose, spacing).nodes.astype(np.float64) / 32767.0


def make_fixed_t32_grid(config: CameraConfig, pose, frac_bits=15, total_bits=None,
                        spacing=32, rounding="nearest_even") -> FixedGrid:
    if total_bits is None:
        total_bits = frac_bits + 1
    import sys
    from pathlib import Path
    codex = Path(__file__).resolve().parents[1]
    if str(codex) not in sys.path:
        sys.path.insert(0, str(codex))
    from experiments.exp02_architecture_tournament.candidate_models import rotation_for_convention
    xs=np.arange(0,config.sensor_w+spacing,spacing,dtype=np.float64)
    ys=np.arange(0,config.sensor_h+spacing,spacing,dtype=np.float64)
    xx,yy=np.meshgrid((xs-config.cx)/config.fx,(ys-config.cy)/config.fy)
    rays=np.stack((xx,yy,np.ones_like(xx)),axis=-1)
    rays/=np.linalg.norm(rays,axis=-1,keepdims=True)
    mat=np.asarray(rotation_for_convention(pose.yaw,pose.pitch,pose.roll,"RzRyRx"))
    fgrid=rays@mat.T
    return FixedGrid.from_float_nodes(fgrid, frac_bits, total_bits, spacing,
                                      config.sensor_w, config.sensor_h, rounding)
