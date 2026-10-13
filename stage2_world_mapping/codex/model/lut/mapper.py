"""Yaw-only horizontal angle lookup mapper."""

from __future__ import annotations

import math

from model.common import CameraConfig, angles_to_world_pixel, wrap_pi


class LutMapper:
    def __init__(self, config: CameraConfig):
        self.config = config
        self.angle_lut = tuple(math.atan((x - config.cx) / config.fx) for x in range(config.sensor_w))

    @property
    def precomputation(self) -> dict[str, int | str]:
        return {"lut_entries": len(self.angle_lut), "atan_evaluations": len(self.angle_lut),
                "notes": "one-time table construction; excluded from per-event runtime counts"}

    def map_angles(self, x: float, y: float, yaw: float) -> tuple[float, float]:
        if int(x) != x or not (0 <= int(x) < self.config.sensor_w):
            raise ValueError("LUT mapper requires an in-range integer pixel column")
        local_az = self.angle_lut[int(x)]
        local_el = math.atan2((y - self.config.cy) / self.config.fy,
                              math.hypot((x - self.config.cx) / self.config.fx, 1.0))
        return wrap_pi(local_az + yaw), local_el

    def map_pixel(self, x: float, y: float, yaw: float) -> tuple[int, int]:
        az, el = self.map_angles(x, y, yaw)
        return angles_to_world_pixel(az, el, self.config)

    @staticmethod
    def estimated_ops_per_event() -> dict[str, int | str]:
        return {"lut_reads": 1, "add_sub": 2, "multiply": 1, "divide": 2,
                "sqrt": 1, "atan": 0, "atan2": 1,
                "notes": "horizontal LUT read; add yaw; constant-scale map quantization; vertical coordinate uses geometric division, sqrt, atan2"}
