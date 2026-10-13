# Codex implementation and experiments

This workspace is owned by Codex for executable reference models and measured
experiments. It does not contain RTL. Architecture interpretation and review
belong to the independent Claude workspace; shared assumptions should be
deliberately agreed before they are treated as competition specifications.

Experiment 01 is a deterministic synthetic rotation-only study. Its known
world features are synthetic ground truth, not competition ground truth.

## Run

From the repository root:

```bash
python3 -m unittest discover -s stage2_world_mapping/codex/tests -v
python3 stage2_world_mapping/codex/experiments/exp01_rotation_only/run.py
```

The experiment plotting step requires Matplotlib. The runner accepts
`--sensor-w`, `--sensor-h`, `--fx`, `--fy`, `--world-w`, `--world-h`, and
`--seed` overrides; the default `fx` and `fy` are labeled synthetic values.

The experiment writes its config, metrics, plots, and summary under
`results/exp01/` in this workspace.
