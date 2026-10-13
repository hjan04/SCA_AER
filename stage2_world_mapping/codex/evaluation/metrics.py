"""Accuracy metrics for directional mapping."""

from __future__ import annotations

import math
from statistics import mean, median

from model.common import CameraConfig, angular_distance_deg, world_pixel_distance


def summarize_errors(mapped_angles, mapped_pixels, truth_angles, truth_pixels,
                     config: CameraConfig) -> dict[str, float | int]:
    angular = [angular_distance_deg(a, b) for a, b in zip(mapped_angles, truth_angles)]
    pixels = [world_pixel_distance(a, b, config) for a, b in zip(mapped_pixels, truth_pixels)]
    if not angular:
        raise ValueError("cannot summarize an empty sample")
    ordered = sorted(angular)
    p95 = ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]
    return {"n": len(angular), "mean_angular_error_deg": mean(angular),
            "median_angular_error_deg": median(angular), "p95_angular_error_deg": p95,
            "max_angular_error_deg": max(angular), "mean_world_pixel_error": mean(pixels),
            "max_world_pixel_error": max(pixels)}
