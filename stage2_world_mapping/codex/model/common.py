"""Shared geometry and equirectangular-map helpers."""

from __future__ import annotations

from dataclasses import dataclass
import math


TAU = 2.0 * math.pi


def wrap_pi(angle: float) -> float:
    """Wrap radians to [-pi, pi)."""
    return (angle + math.pi) % TAU - math.pi


@dataclass(frozen=True)
class CameraConfig:
    sensor_w: int = 960
    sensor_h: int = 720
    world_w: int = 256
    world_h: int = 128
    fx: float = 800.0
    fy: float = 800.0
    cx: float | None = None
    cy: float | None = None

    def __post_init__(self) -> None:
        if min(self.sensor_w, self.sensor_h, self.world_w, self.world_h) <= 0:
            raise ValueError("image and map dimensions must be positive")
        if self.fx <= 0 or self.fy <= 0:
            raise ValueError("fx and fy must be positive pixel focal lengths")
        if self.cx is None:
            object.__setattr__(self, "cx", self.sensor_w / 2.0)
        if self.cy is None:
            object.__setattr__(self, "cy", self.sensor_h / 2.0)


def rotation_matrix(yaw: float, pitch: float, roll: float) -> tuple[tuple[float, ...], ...]:
    """Rz(roll) * Ry(yaw) * Rx(pitch), column-vector convention."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    return (
        (cr * cy, cr * sy * sp - sr * cp, cr * sy * cp + sr * sp),
        (sr * cy, sr * sy * sp + cr * cp, sr * sy * cp - cr * sp),
        (-sy, cy * sp, cy * cp),
    )


def rotate_vector(matrix: tuple[tuple[float, ...], ...], vec: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(sum(matrix[r][c] * vec[c] for c in range(3)) for r in range(3))  # type: ignore[return-value]


def transpose(matrix: tuple[tuple[float, ...], ...]) -> tuple[tuple[float, ...], ...]:
    return tuple(tuple(matrix[c][r] for c in range(3)) for r in range(3))


def angles_to_ray(azimuth: float, elevation: float) -> tuple[float, float, float]:
    ce = math.cos(elevation)
    return (math.sin(azimuth) * ce, math.sin(elevation), math.cos(azimuth) * ce)


def ray_to_angles(ray: tuple[float, float, float]) -> tuple[float, float]:
    x, y, z = ray
    az = math.atan2(x, z)
    el = math.atan2(y, math.hypot(x, z))
    return wrap_pi(az), el


def ray_to_world_pixel(ray: tuple[float, float, float], cfg: CameraConfig) -> tuple[int, int]:
    az, el = ray_to_angles(ray)
    return angles_to_world_pixel(az, el, cfg)


def angles_to_world_pixel(az: float, el: float, cfg: CameraConfig) -> tuple[int, int]:
    wx = int(math.floor(((az + math.pi) / TAU) * cfg.world_w)) % cfg.world_w
    bounded_el = max(-math.pi / 2, min(math.pi / 2, el))
    wy = int(math.floor(((math.pi / 2 - bounded_el) / math.pi) * cfg.world_h))
    return wx, min(cfg.world_h - 1, max(0, wy))


def pixel_ray(x: float, y: float, cfg: CameraConfig) -> tuple[float, float, float]:
    return ((x - cfg.cx) / cfg.fx, (y - cfg.cy) / cfg.fy, 1.0)


def project_world_direction(
    azimuth: float, elevation: float, yaw: float, pitch: float, roll: float,
    cfg: CameraConfig,
) -> tuple[float, float] | None:
    """Project a stationary world ray into the camera, returning subpixel (u,v)."""
    world_ray = angles_to_ray(azimuth, elevation)
    camera_ray = rotate_vector(transpose(rotation_matrix(yaw, pitch, roll)), world_ray)
    if camera_ray[2] <= 0:
        return None
    u = cfg.fx * camera_ray[0] / camera_ray[2] + cfg.cx
    v = cfg.fy * camera_ray[1] / camera_ray[2] + cfg.cy
    if not (0 <= u <= cfg.sensor_w - 1 and 0 <= v <= cfg.sensor_h - 1):
        return None
    return u, v


def angular_distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Spherical great-circle angle in radians."""
    va, vb = angles_to_ray(*a), angles_to_ray(*b)
    dot = max(-1.0, min(1.0, sum(va[i] * vb[i] for i in range(3))))
    cross = (va[1] * vb[2] - va[2] * vb[1],
             va[2] * vb[0] - va[0] * vb[2],
             va[0] * vb[1] - va[1] * vb[0])
    return math.atan2(math.sqrt(sum(component * component for component in cross)), dot)


def angular_distance_deg(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.degrees(angular_distance(a, b))


def world_pixel_distance(a: tuple[int, int], b: tuple[int, int], cfg: CameraConfig) -> float:
    dx = abs(a[0] - b[0])
    dx = min(dx, cfg.world_w - dx)
    dy = abs(a[1] - b[1])
    return math.hypot(dx, dy)
