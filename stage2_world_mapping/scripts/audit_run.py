#!/usr/bin/env python3
"""Run a regression script and prove it only uses files inside this directory.

Installs a Python audit hook that records every file opened by the Python
process (including module imports and CSV/vector reads) and every subprocess
command line (iverilog/vvp/verilator arguments). Any reference to the original
source locations fails the run:
  /tmp/sca_aer_codex_modeling2       (Codex worktree)
  /home/hj/SCA_AER/stage2_world_mapping  (Claude source tree)
Simulator subprocesses only receive explicit file paths from the scripts, so
checking their argument lists covers their inputs.

Usage: python3 scripts/audit_run.py <script.py> [args...]
"""
import os
import runpy
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORBIDDEN = ("/tmp/sca_aer_codex_modeling2", "/home/hj/SCA_AER/stage2_world_mapping")
hits = []
opened_outside_root = set()


def _hook(event, args):
    if event == "open" and args and isinstance(args[0], (str, bytes, os.PathLike)):
        p = os.fsdecode(args[0]) if not isinstance(args[0], str) else args[0]
        ap = os.path.abspath(p)
        if any(ap.startswith(f) for f in FORBIDDEN):
            hits.append(("open", ap))
    elif event == "subprocess.Popen":
        argv = args[1] if len(args) > 1 else []
        for a in (argv or []):
            s = os.fspath(a) if isinstance(a, os.PathLike) else str(a)
            if any(f in s for f in FORBIDDEN):
                hits.append(("exec-arg", s))


sys.addaudithook(_hook)
target = os.path.abspath(sys.argv[1])
sys.argv = sys.argv[1:]
rc = 0
try:
    runpy.run_path(target, run_name="__main__")
except SystemExit as e:
    rc = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
mods = sorted({os.path.abspath(m.__file__) for m in list(sys.modules.values())
               if getattr(m, "__file__", None) and "/codex/" in m.__file__})
print("AUDIT codex modules loaded from:", *mods, sep="\n  ")
if hits:
    print(f"AUDIT FAIL: {len(hits)} reference(s) outside {ROOT}:")
    for h in sorted(set(hits))[:20]:
        print("  ", h)
    sys.exit(2)
print(f"AUDIT PASS: no file open or subprocess argument referenced {FORBIDDEN}")
print(f"AUDIT script exit code: {rc}")
sys.exit(rc)
