"""Floating-point geometric golden reference."""

from __future__ import annotations

import math

from model.common import CameraConfig, pixel_ray, ray_to_angles, ray_to_world_pixel, rotate_vector, rotation_matrix


class GoldenMapper:
    def __init__(self, config: CameraConfig):
        self.config = config

    def map_angles(self, x: float, y: float, yaw: float, pitch: float = 0.0, roll: float = 0.0) -> tuple[float, float]:
        ray = pixel_ray(x, y, self.config)
        world = rotate_vector(rotation_matrix(yaw, pitch, roll), ray)
        return ray_to_angles(world)

    def map_pixel(self, x: float, y: float, yaw: float, pitch: float = 0.0, roll: float = 0.0) -> tuple[int, int]:
        ray = pixel_ray(x, y, self.config)
        world = rotate_vector(rotation_matrix(yaw, pitch, roll), ray)
        return ray_to_world_pixel(world, self.config)

    @staticmethod
    def estimated_ops_per_event() -> dict[str, int | str]:
        return {"lut_reads": 0, "add_sub": 8, "multiply": 9, "divide": 2,
                "sqrt": 1, "atan": 0, "atan2": 2,
                "notes": "rotation matrix products + pinhole divisions + atan2; pose sin/cos setup excluded"}
