from __future__ import annotations

import math
import pathlib
import sys
import unittest

CODEX = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CODEX))

from model.common import CameraConfig, angular_distance_deg, project_world_direction, wrap_pi
from model.golden.mapper import GoldenMapper
from model.lut.mapper import LutMapper
from model.linear.mapper import LinearMapper
from synthetic.generator import project_feature


class MappingTests(unittest.TestCase):
    def setUp(self):
        self.cfg = CameraConfig(sensor_w=320, sensor_h=240, world_w=256, world_h=128,
                                fx=200.0, fy=200.0)
        self.golden = GoldenMapper(self.cfg)
        self.lut = LutMapper(self.cfg)
        self.linear = LinearMapper(self.cfg)

    def test_zero_yaw_center_pixel_is_zero_azimuth(self):
        az, _ = self.golden.map_angles(self.cfg.cx, self.cfg.cy, 0.0)
        self.assertAlmostEqual(az, 0.0, places=12)

    def test_stationary_plus_30_degrees_survives_yaw_sweep(self):
        feature = math.radians(30)
        for yaw_deg in range(0, 41, 2):
            event = project_feature(feature, 0.0, math.radians(yaw_deg), yaw_deg, 0, self.cfg)
            self.assertIsNotNone(event)
            mapped = self.golden.map_angles(event.x, event.y, event.yaw)
            self.assertLess(angular_distance_deg(mapped, (feature, 0.0)), 0.6)

    def test_positive_and_negative_yaw_signs(self):
        center = self.cfg.cx, self.cfg.cy
        pos = self.golden.map_angles(*center, math.radians(12))[0]
        neg = self.golden.map_angles(*center, math.radians(-12))[0]
        self.assertGreater(pos, 0)
        self.assertLess(neg, 0)
        self.assertAlmostEqual(pos, -neg, places=12)

    def test_angle_wrap(self):
        self.assertAlmostEqual(wrap_pi(math.radians(190)), math.radians(-170))
        self.assertAlmostEqual(wrap_pi(math.radians(-190)), math.radians(170))
        self.assertEqual(wrap_pi(math.pi), -math.pi)

    def test_equirectangular_wrap_across_plus_minus_180(self):
        for az_deg, yaw_deg in ((179, 179), (-179, -179)):
            uv = project_world_direction(math.radians(az_deg), 0.0,
                                         math.radians(yaw_deg), 0.0, 0.0, self.cfg)
            self.assertIsNotNone(uv)
            mapped = self.golden.map_angles(*uv, math.radians(yaw_deg))
            self.assertLess(angular_distance_deg(mapped, (math.radians(az_deg), 0.0)), 1e-9)

    def test_image_boundary_pixels_are_finite_and_in_map(self):
        for x, y in ((0, 0), (319, 0), (0, 239), (319, 239)):
            az, el = self.golden.map_angles(x, y, 0.0)
            wx, wy = self.golden.map_pixel(x, y, 0.0)
            self.assertTrue(math.isfinite(az) and math.isfinite(el))
            self.assertTrue(0 <= wx < self.cfg.world_w)
            self.assertTrue(0 <= wy < self.cfg.world_h)

    def test_forward_projection_inverse_consistency(self):
        for az_deg, el_deg, yaw_deg in ((30, 0, 17), (-45, 20, -10), (55, -25, 30)):
            uv = project_world_direction(math.radians(az_deg), math.radians(el_deg),
                                         math.radians(yaw_deg), 0, 0, self.cfg)
            self.assertIsNotNone(uv)
            mapped = self.golden.map_angles(*uv, math.radians(yaw_deg))
            expected = math.radians(az_deg), math.radians(el_deg)
            self.assertLess(angular_distance_deg(mapped, expected), 1e-9)

    def test_lut_matches_golden_for_integer_columns(self):
        for x in (0, 1, 80, 159, 160, 240, 319):
            for y in (0, 120, 239):
                yaw = math.radians(13)
                g = self.golden.map_angles(x, y, yaw)
                l = self.lut.map_angles(x, y, yaw)
                self.assertLess(angular_distance_deg(g, l), 1e-8)

    def test_linear_is_finite_and_measurably_approximates_golden(self):
        errors = []
        for x in range(self.cfg.sensor_w):
            g = self.golden.map_angles(x, self.cfg.cy, 0.0)
            a = self.linear.map_angles(x, self.cfg.cy, 0.0)
            errors.append(angular_distance_deg(g, a))
        self.assertGreater(max(errors), 0.01)
        self.assertLess(max(errors), 4.0)

    def test_multiple_elevations_recover_consistently(self):
        for elevation_deg in (-30, -10, 0, 15, 30):
            event = project_feature(math.radians(20), math.radians(elevation_deg),
                                    math.radians(8), 0, 1, self.cfg)
            self.assertIsNotNone(event)
            mapped = self.golden.map_angles(event.x, event.y, event.yaw)
            self.assertLess(angular_distance_deg(mapped,
                                                 (math.radians(20), math.radians(elevation_deg))), 0.7)

    def test_world_coordinate_quantization_is_bounded(self):
        for x in (0, self.cfg.cx, self.cfg.sensor_w - 1):
            for y in (0, self.cfg.cy, self.cfg.sensor_h - 1):
                wx, wy = self.golden.map_pixel(x, y, math.radians(178))
                self.assertTrue(0 <= wx < self.cfg.world_w)
                self.assertTrue(0 <= wy < self.cfg.world_h)


if __name__ == "__main__":
    unittest.main()
