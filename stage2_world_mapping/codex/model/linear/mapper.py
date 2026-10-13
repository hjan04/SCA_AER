"""Yaw-only center-slope linear horizontal approximation."""

from __future__ import annotations

import math

from model.common import CameraConfig, angles_to_world_pixel, wrap_pi


class LinearMapper:
    def __init__(self, config: CameraConfig):
        self.config = config
        half = config.sensor_w / 2.0
        self.k = math.atan(half / config.fx) / half

    def map_angles(self, x: float, y: float, yaw: float) -> tuple[float, float]:
        local_az = self.k * (x - self.config.cx)
        local_el = math.atan2((y - self.config.cy) / self.config.fy,
                              math.hypot((x - self.config.cx) / self.config.fx, 1.0))
        return wrap_pi(local_az + yaw), local_el

    def map_pixel(self, x: float, y: float, yaw: float) -> tuple[int, int]:
        az, el = self.map_angles(x, y, yaw)
        return angles_to_world_pixel(az, el, self.config)

    @staticmethod
    def estimated_ops_per_event() -> dict[str, int | str]:
        return {"lut_reads": 0, "add_sub": 3, "multiply": 2, "divide": 2,
                "sqrt": 1, "atan": 0, "atan2": 1,
                "notes": "subtraction, slope multiply, yaw add, constant-scale quantization; vertical coordinate uses geometric division, sqrt, atan2"}
