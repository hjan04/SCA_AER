"""Mapper registry for Experiment 01."""

from model.golden.mapper import GoldenMapper
from model.lut.mapper import LutMapper
from model.linear.mapper import LinearMapper


def make_mappers(config):
    return {"G": GoldenMapper(config), "L": LutMapper(config), "A": LinearMapper(config)}
