"""Conceptual source-level runtime and setup operation estimates."""

from __future__ import annotations

from model.golden.mapper import GoldenMapper
from model.lut.mapper import LutMapper
from model.linear.mapper import LinearMapper


def operation_rows(config):
    models = [("G", GoldenMapper), ("L", LutMapper), ("A", LinearMapper)]
    rows = []
    for name, cls in models:
        row = {"model": name, "lut_reads": 0, "add_sub": 0, "multiply": 0,
               "divide": 0, "sqrt": 0, "atan": 0, "atan2": 0,
               "lut_entries_setup": 0, "atan_setup": 0, "notes": ""}
        row.update(cls.estimated_ops_per_event())
        if name == "L":
            mapper = cls(config)
            row["lut_entries_setup"] = mapper.precomputation["lut_entries"]
            row["atan_setup"] = mapper.precomputation["atan_evaluations"]
            row["notes"] += "; setup cost reported separately"
        rows.append(row)
    return rows
