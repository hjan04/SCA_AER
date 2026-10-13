"""Exp02 candidates: LUT, global/PWL angle models, and per-pose warp grids."""
from __future__ import annotations
from bisect import bisect_right
from dataclasses import dataclass
import math
import numpy as np
from model.common import CameraConfig, pixel_ray, ray_to_angles, rotate_vector, rotation_matrix as exp01_rotation_matrix, wrap_pi


def _multiply(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def rotation_for_convention(yaw, pitch, roll, convention="RzRyRx"):
    """Column-vector convention; RzRyRx matches Exp01 Model G."""
    if convention == "RzRyRx":
        return exp01_rotation_matrix(yaw, pitch, roll)
    if convention != "RxRyRz":
        raise ValueError(f"unsupported Euler convention: {convention}")
    cy, sy, cp, sp, cr, sr = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
    rx = ((1., 0., 0.), (0., cp, -sp), (0., sp, cp))
    ry = ((cy, 0., sy), (0., 1., 0.), (-sy, 0., cy))
    rz = ((cr, -sr, 0.), (sr, cr, 0.), (0., 0., 1.))
    return _multiply(_multiply(rx, ry), rz)


@dataclass(frozen=True)
class Pose:
    yaw: float
    pitch: float = 0.0
    roll: float = 0.0


def pixel_to_world_ray(x, y, config, pose, convention="RzRyRx"):
    return rotate_vector(rotation_for_convention(pose.yaw, pose.pitch, pose.roll, convention), pixel_ray(x, y, config))


class GoldenReference:
    name, mode = "Golden", "three_axis"
    def __init__(self, config, convention="RzRyRx"):
        self.config, self.convention = config, convention
    def map_angles(self, x, y, pose):
        return ray_to_angles(pixel_to_world_ray(x, y, self.config, pose, self.convention))


class FullColumnLUT:
    """C0-a: exact horizontal column-angle LUT; yaw only."""
    name, mode = "C0a-Full-Column-LUT", "yaw_only"
    def __init__(self, config):
        self.config = config
        vals = np.arctan((np.arange(config.sensor_w) - config.cx) / config.fx)
        self.table = np.rint(vals * (1 << 13)) / (1 << 13)  # signed Q3.13
    def map_angles(self, x, y, pose):
        if pose.pitch != 0.0 or pose.roll != 0.0:
            raise ValueError("C0-a is valid only for yaw-only poses")
        if int(x) != x or not 0 <= int(x) < self.config.sensor_w:
            raise ValueError("column LUT requires integer in-range x")
        X, Y = (x - self.config.cx) / self.config.fx, (y - self.config.cy) / self.config.fy
        # Exact local elevation of the full ray; it depends on x and y.
        return wrap_pi(float(self.table[int(x)]) + pose.yaw), math.atan2(Y, math.hypot(X, 1.0))


class FullRay2DLUT:
    """C0-b: 2-D Q1.15 unit-ray table, followed by full pose rotation."""
    name, mode = "C0b-2D-Ray-LUT", "three_axis"
    def __init__(self, config, component_bits=16):
        self.config = config
        xs = (np.arange(config.sensor_w) - config.cx) / config.fx
        ys = (np.arange(config.sensor_h) - config.cy) / config.fy
        xx, yy = np.meshgrid(xs, ys)
        norm = np.sqrt(xx * xx + yy * yy + 1.0)
        rays = np.stack((xx / norm, yy / norm, np.ones_like(xx) / norm), axis=-1)
        self.scale = (1 << (component_bits - 1)) - 1
        self.rays = np.clip(np.rint(rays * self.scale), -self.scale - 1, self.scale).astype(np.int16)
    def map_angles(self, x, y, pose, convention="RzRyRx"):
        ray = self.rays[int(y), int(x)].astype(np.float64) / self.scale
        mat = rotation_for_convention(pose.yaw, pose.pitch, pose.roll, convention)
        return ray_to_angles(rotate_vector(mat, tuple(ray)))


class GlobalLinear:
    mode = "three_axis"
    def __init__(self, config, convention="RzRyRx", fixed=False):
        self.config, self.convention, self.fixed = config, convention, fixed
        self.max_dx = max(abs(config.cx), abs(config.sensor_w - 1 - config.cx))
        self.k = math.atan(self.max_dx / config.fx) / self.max_dx
        if fixed:
            self.k = round(self.k * (1 << 16)) / (1 << 16)
        self.name = "Global-Linear-Q2.16" if fixed else "Global-Linear-float"
    def local_angles(self, x, y):
        X, Y = (x - self.config.cx) / self.config.fx, (y - self.config.cy) / self.config.fy
        return self.k * (x - self.config.cx), math.atan2(Y, math.hypot(X, 1.0))
    def map_angles(self, x, y, pose):
        az, el = self.local_angles(x, y)
        if pose.pitch == 0.0 and pose.roll == 0.0:
            return wrap_pi(az + pose.yaw), el
        ce = math.cos(el)
        ray = (math.sin(az) * ce, math.sin(el), math.cos(az) * ce)
        mat = rotation_for_convention(pose.yaw, pose.pitch, pose.roll, self.convention)
        return ray_to_angles(rotate_vector(mat, ray))


class PiecewiseCurve:
    """Symmetric pixel-domain PWL fit of atan(dx/fx); fixed variant is Q2.16."""
    FRAC_BITS, COEFF_BITS = 16, 18
    def __init__(self, config, segments, fixed=False):
        self.config, self.segments, self.fixed = config, segments, fixed
        self.max_dx = max(abs(config.cx), abs(config.sensor_w - 1 - config.cx))
        self.bounds = np.linspace(0.0, self.max_dx, segments + 1)
        self.slopes, self.intercepts = [], []
        for i in range(segments):
            lo, hi = self.bounds[i:i + 2]
            f0, f1 = math.atan(lo / config.fx), math.atan(hi / config.fx)
            a = (f1 - f0) / (hi - lo)
            b = f0 - a * lo
            if fixed:
                a = round(a * (1 << self.FRAC_BITS)) / (1 << self.FRAC_BITS)
                b = round(b * (1 << self.FRAC_BITS)) / (1 << self.FRAC_BITS)
            self.slopes.append(a); self.intercepts.append(b)
    def evaluate(self, offset):
        sign, mag = (-1.0 if offset < 0 else 1.0), abs(offset)
        i = min(self.segments - 1, max(0, bisect_right(self.bounds, mag) - 1))
        return sign * (self.slopes[i] * mag + self.intercepts[i])


class PiecewiseMapper:
    mode = "three_axis"
    def __init__(self, config, segments, fixed=False, convention="RzRyRx"):
        self.config, self.segments, self.fixed, self.convention = config, segments, fixed, convention
        self.curve = PiecewiseCurve(config, segments, fixed)
        self.name = f"PWL-{segments}-{'Q2.16' if fixed else 'float'}"
    def local_angles(self, x, y):
        X, Y = (x - self.config.cx) / self.config.fx, (y - self.config.cy) / self.config.fy
        return self.curve.evaluate(x - self.config.cx), math.atan2(Y, math.hypot(X, 1.0))
    def map_angles(self, x, y, pose):
        az, el = self.local_angles(x, y)
        if pose.pitch == 0.0 and pose.roll == 0.0:
            return wrap_pi(az + pose.yaw), el
        ce = math.cos(el)
        ray = (math.sin(az) * ce, math.sin(el), math.cos(az) * ce)
        mat = rotation_for_convention(pose.yaw, pose.pitch, pose.roll, self.convention)
        return ray_to_angles(rotate_vector(mat, ray))


class InterpolatedAngleLUT:
    """Power-of-two sampled Q3.13 column angle LUT with linear interpolation."""
    mode = "yaw_only"
    def __init__(self, config, spacing):
        self.config, self.spacing = config, spacing
        self.xnodes = np.arange(0, config.sensor_w + spacing, spacing, dtype=np.int64)
        v = np.arctan((self.xnodes - config.cx) / config.fx)
        self.values = np.rint(v * (1 << 13)) / (1 << 13)
        self.name = f"Column-LUT-Interp-{spacing}px"
    def map_angles(self, x, y, pose):
        if pose.pitch != 0.0 or pose.roll != 0.0:
            raise ValueError("column interpolation LUT is yaw-only")
        i = min(int(x) // self.spacing, len(self.xnodes) - 2)
        f = (x - self.xnodes[i]) / self.spacing
        az = (1.0 - f) * self.values[i] + f * self.values[i + 1]
        X, Y = (x - self.config.cx) / self.config.fx, (y - self.config.cy) / self.config.fy
        return wrap_pi(float(az) + pose.yaw), math.atan2(Y, math.hypot(X, 1.0))


class WarpGrid:
    """Per-pose bilinear interpolation of Q1.15 world-direction vector nodes."""
    mode = "three_axis"
    def __init__(self, config, pose, spacing, convention="RzRyRx", node_bits=16):
        self.config, self.pose, self.spacing = config, pose, spacing
        self.xnodes = np.arange(0, config.sensor_w + spacing, spacing, dtype=np.int64)
        self.ynodes = np.arange(0, config.sensor_h + spacing, spacing, dtype=np.int64)
        mat = np.asarray(rotation_for_convention(pose.yaw, pose.pitch, pose.roll, convention))
        xx, yy = np.meshgrid((self.xnodes - config.cx) / config.fx, (self.ynodes - config.cy) / config.fy)
        rays = np.stack((xx, yy, np.ones_like(xx)), axis=-1)
        rays /= np.linalg.norm(rays, axis=-1, keepdims=True)
        world = rays @ mat.T
        self.node_count = len(self.xnodes) * len(self.ynodes)
        self.scale = (1 << (node_bits - 1)) - 1
        self.nodes = np.clip(np.rint(world * self.scale), -self.scale - 1, self.scale).astype(np.int16)
    def map_angles(self, x, y):
        ix = min(int(x) // self.spacing, len(self.xnodes) - 2)
        iy = min(int(y) // self.spacing, len(self.ynodes) - 2)
        tx, ty = (x - self.xnodes[ix]) / self.spacing, (y - self.ynodes[iy]) / self.spacing
        q00, q10 = self.nodes[iy, ix].astype(float) / self.scale, self.nodes[iy, ix + 1].astype(float) / self.scale
        q01, q11 = self.nodes[iy + 1, ix].astype(float) / self.scale, self.nodes[iy + 1, ix + 1].astype(float) / self.scale
        top, bot = (1.0 - tx) * q00 + tx * q10, (1.0 - tx) * q01 + tx * q11
        return ray_to_angles((1.0 - ty) * top + ty * bot)
