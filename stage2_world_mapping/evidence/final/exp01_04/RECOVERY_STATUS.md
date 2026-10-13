# Exp01–04 compact evidence recovery status

The audited project contains no original Exp01–04 result directories. `codex/results/` contains only Exp05 and Exp05b CSVs. No broad Exp01–04 experiments were rerun.

Two Sept 22 source recordings and the restored original Exp03 decoder, format notes, analyzer, and run script are now present and hashed in [../REAL_DATA_PROVENANCE.md](../REAL_DATA_PROVENANCE.md). Both Sept 22 recordings were processed with the restored decoder in bounded chunks; compact per-frame traffic statistics and the peak sequence replay are available under `../real_data_summary/` and `../peak_sequence/`. The Sept 15 source recording remains unavailable, and the original full Exp03 locality/bank analysis outputs were not regenerated. The compact two-frame NPZ remains available for the exact frames 900/901 validation.

Available secondary evidence remains the audit summaries:

- `FINAL_TECHNICAL_AUDIT.md`
- `CLAIMS_AND_EVIDENCE.md`

Unavailable primary evidence includes Exp01 ray-projection comparisons; Exp02 PWL/T32/T64 tournament vectors/configs; Sept15 raw data and historical Exp03 locality outputs; and Exp04 bank/lane/merge sweep data/configs. The current Sept 22 peak-throughput evidence is based on the recovered sources and is detailed separately in [../PEAK_FRAME_RTL.md](../PEAK_FRAME_RTL.md).
