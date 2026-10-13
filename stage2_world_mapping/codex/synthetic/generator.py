"""Deterministic stationary-world-feature projection for Experiment 01."""

from __future__ import annotations

from dataclasses import dataclass
import math
import random

from model.common import CameraConfig, project_world_direction


@dataclass(frozen=True)
class Event:
    x: int
    y: int
    polarity: int
    timestamp: int
    yaw: float
    truth_azimuth: float
    truth_elevation: float
    feature_id: int


def project_feature(azimuth: float, elevation: float, yaw: float, timestamp: int,
                    feature_id: int, config: CameraConfig, pitch: float = 0.0,
                    roll: float = 0.0) -> Event | None:
    uv = project_world_direction(azimuth, elevation, yaw, pitch, roll, config)
    if uv is None:
        return None
    x, y = int(math.floor(uv[0] + 0.5)), int(math.floor(uv[1] + 0.5))
    if not (0 <= x < config.sensor_w and 0 <= y < config.sensor_h):
        return None
    return Event(x, y, feature_id & 1, timestamp, yaw, azimuth, elevation, feature_id)


def rotation_track(azimuth: float, elevation: float, yaws: list[float],
                   config: CameraConfig) -> list[Event]:
    return [event for i, yaw in enumerate(yaws)
            if (event := project_feature(azimuth, elevation, yaw, i, 0, config)) is not None]


def seeded_static_field(count: int, seed: int, az_min_deg: float = -75,
                        az_max_deg: float = 75, el_min_deg: float = -35,
                        el_max_deg: float = 35) -> list[tuple[float, float]]:
    rng = random.Random(seed)
    return [(math.radians(rng.uniform(az_min_deg, az_max_deg)),
             math.radians(rng.uniform(el_min_deg, el_max_deg))) for _ in range(count)]
