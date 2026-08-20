# Cadence Genus Environment Discovery

Stage: 5A

Branch created for this work: `stage5-genus-ppa`

Starting milestone:

```text
4fc14f1 Complete equal-bandwidth AER comparison through Stage 4
```

## Scope

This document records the preliminary synthesis-environment investigation
performed in the local WSL2 checkout. It intentionally does not invent Cadence,
PDK, Liberty, or LEF paths. Final PPA synthesis has not been run.

## Environment Status

The previous Stage 5A discovery was executed in local WSL2, not on the
intended SCA Cadence server.

```text
hostname: HJPC
OS context: WSL2
repository: /home/hj/SCA_AER
branch: stage5-genus-ppa
```

Therefore:

```text
Cadence availability has NOT yet been checked on the SCA server.
Genus availability on the SCA server is UNKNOWN.
The official competition 45 nm PDK is UNKNOWN.
Local gscl45nm is only a generic fallback candidate.
Official PPA work remains blocked until the SCA server environment is inspected.
```

## Stage 4 Regression Status

The existing Stage 4 RTL was reverified before environment discovery.

```text
scripts/run_baseline_sim.sh   PASS
scripts/run_adaptive_sim.sh   PASS
scripts/run_link_sim.sh       PASS
```

Observed pass markers:

```text
BASELINE DIRECTED TESTS: PASS
ADAPTIVE DIRECTED TESTS: PASS
LINK SERIALIZER DIRECTED TESTS: PASS
BASELINE LINK DIRECTED TESTS: PASS
ADAPTIVE LINK DIRECTED TESTS: PASS
STAGE4 LINK DIRECTED TESTS: PASS
```

## Genus Availability

Genus was not found in the local WSL2 shell environment.

Commands checked:

```bash
which genus
command -v genus
```

Result:

```text
Genus executable path: NOT FOUND
Genus version: NOT AVAILABLE
Launch status: blocked because no genus executable is on PATH
```

No Genus read/elaboration smoke test was run because the executable is not
available.

## Environment Setup Discovery

The shell module command is not available in this environment:

```bash
type module
```

Result:

```text
module: not found
```

Filtered environment-variable inspection for Cadence, Genus, PDK, library,
technology, and license-related names found no usable Cadence or PDK setup
variables in the local WSL2 shell. No license values are documented here.

Targeted inspection of likely setup locations and shell startup files did not
find a Cadence/Genus setup script.

Required setup command:

```text
UNKNOWN
```

Action required before Stage 5B:

```text
Obtain the official competition/server Cadence setup command from the lab,
course staff, or server administrator, then rerun Stage 5A discovery.
```

## 45 nm PDK / Library Discovery

The only 45 nm technology candidate found in the local WSL2 shell is the Qflow
`gscl45nm` technology. It is classified as `GENERIC_45NM`, not as the official
competition PDK.

```text
PDK/library name: gscl45nm
PDK root: /usr/local/share/qflow/tech/gscl45nm
Technology origin: Qflow/OpenROAD-style educational 45 nm files
Competition Cadence PDK status: NOT CONFIRMED
Classification: GENERIC_45NM
```

Important limitation:

```text
This is not confirmed to be the competition Cadence educational 45 nm PDK.
Do not use it as the final Cadence PPA target unless the competition
environment explicitly confirms it.
```

The local `gscl45nm.prm` file includes the note:

```text
Note that these values are totally bogus!
```

The local `gscl45nm.tech` file identifies the rules as:

```text
NCSU FreePDK45: Open rules and DRC
```

## Liberty Timing Library

One plausible 45 nm Liberty timing file was found:

```text
/usr/local/share/qflow/tech/gscl45nm/gscl45nm.lib
```

Library metadata:

```text
library: gscl45nm
default operating condition: typical
nominal process: 1
nominal voltage: 1.1 V
nominal temperature: 27 C
time unit: 1 ns
capacitive load unit: 1 pF
```

Available PVT corners found for this library:

```text
typical: process 1, voltage 1.1 V, temperature 27 C
```

No TT/SS/FF multi-corner Liberty set was found in the current environment.

Recommended initial comparison corner, if this library is approved for use:

```text
typical
```

Reason:

```text
It is the only available operating condition in the discovered 45 nm Liberty
file. It should be used only if the competition confirms that gscl45nm is an
acceptable target library.
```

## Physical-Design Files

Files found under `/usr/local/share/qflow/tech/gscl45nm`:

```text
gscl45nm.gds
gscl45nm.lef
gscl45nm.lib
gscl45nm.magicrc
gscl45nm.par
gscl45nm.prm
gscl45nm.sh
gscl45nm.sp
gscl45nm.tech
gscl45nm.v
gscl45nm_setup.tcl
```

LEF files:

```text
Technology LEF: not separate in the discovered setup
Standard-cell LEF: /usr/local/share/qflow/tech/gscl45nm/gscl45nm.lef
Combined LEF status: gscl45nm.sh sets techleffile="" and leffile=gscl45nm.lef
```

QRC/extraction files:

```text
No *.qrc, *.ict, *.tch, *.captable, or extraction technology file was found
under the discovered gscl45nm root.
```

## Standard-Cell Library Contents

Representative cells found in `gscl45nm.lib`:

```text
Inverters: INVX1, INVX2, INVX4, INVX8
Buffers: BUFX2, BUFX4
Clock buffers: CLKBUF1, CLKBUF2, CLKBUF3
NAND: NAND2X1, NAND3X1
NOR: NOR2X1, NOR3X1
Flip-flops: DFFNEGX1, DFFPOSX1, DFFSR
Latch: LATCH
AOI/OAI examples: AOI21X1, AOI22X1, OAI21X1
```

Specialized cells:

```text
Clock-gating cells: not found
Multi-bit flip-flops: not found
Multi-Vt variants: not apparent from cell names
Multiple drive strengths: present for selected cells such as INV, BUF, CLKBUF
```

## SRAM / Memory Availability

No SRAM macros, memory Liberty files, memory LEF files, or memory compiler were
found for the discovered `gscl45nm` 45 nm technology.

Unrelated non-45 nm educational PDK files exist under:

```text
/home/hj/ETRI-0.5um-CMOS-MPW-Std-Cell-DK
```

Those files are not candidates for Stage 5 AER PPA.

## Existing Repository Synthesis Material

No existing repository synthesis files were found:

```text
*.tcl
*.sdc
*.lib
*.lib.gz
*.lef
```

The project documentation mentions future Genus work, but no reusable checked
Genus scripts or constraints currently exist.

## Synthesis Tops

### Legacy Baseline

Top module:

```text
aer_baseline_top
```

Required RTL source files:

```text
rtl/common/aer_event_capture.sv
rtl/common/aer_output_handshake.sv
rtl/common/rr_arbiter.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/baseline/aer_baseline_packetizer.sv
rtl/baseline/aer_baseline_top.sv
```

### Transport-Normalized Baseline

Top module:

```text
aer_baseline_link_top
```

Required RTL source files:

```text
rtl/common/aer_event_capture.sv
rtl/common/rr_arbiter.sv
rtl/common/aer_link_serializer.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/baseline/aer_baseline_packetizer.sv
rtl/baseline/aer_baseline_link_top.sv
```

### Transport-Normalized Adaptive

Top module:

```text
aer_adaptive_link_top
```

Required RTL source files:

```text
rtl/common/aer_event_capture.sv
rtl/common/rr_arbiter.sv
rtl/common/aer_link_serializer.sv
rtl/baseline/aer_row_col_arbiter.sv
rtl/adaptive/aer_sparse_packetizer.sv
rtl/adaptive/aer_dense_packetizer.sv
rtl/adaptive/aer_block_occupancy.sv
rtl/adaptive/aer_dense_block_selector.sv
rtl/adaptive/aer_mode_controller.sv
rtl/adaptive/aer_adaptive_link_top.sv
```

Notes:

```text
rtl/common/aer_link_deserializer.sv is a common receiver/deserializer used for
verification. It is not part of the baseline-link or adaptive-link DUT PPA
tops unless a future receiver-side PPA study is added.

rtl/aer_tx_baseline.sv and rtl/aer_tx_hybrid.sv are old experimental RTL and
are not Stage 5 synthesis candidates.
```

## Clock and Reset

All three synthesis tops use the same clock and reset interface:

```text
Clock port: clk
Reset port: rst_n
Reset polarity: active low
Reset behavior: asynchronous reset in always_ff blocks using
                @(posedge clk or negedge rst_n)
```

Baseline-link and adaptive-link can use the same clock constraint for the
primary fair comparison.

No final clock period is selected in Stage 5A.

## Genus Read / Elaboration Smoke Test

Status:

```text
Legacy baseline: NOT RUN, blocked by missing Genus executable
Baseline-link:   NOT RUN, blocked by missing Genus executable
Adaptive-link:   NOT RUN, blocked by missing Genus executable
```

Meaningful Genus warnings/errors:

```text
No Genus warnings/errors are available because Genus could not be launched.
The environment failure is: genus executable not found on PATH.
```

## Power-Analysis Capability

Power-analysis support could not be validated because Genus is unavailable.

Preferred future methodology after Cadence setup is available:

```text
1. Generate activity from identical Stage 4 representative simulations.
2. Convert or export activity as SAIF if supported by the simulation flow.
3. Use the same SAIF/activity methodology for baseline-link and adaptive-link.
4. Use vectorless activity only as a fallback or secondary sensitivity point.
```

Candidate power methods to investigate once Genus is available:

```text
SAIF-based activity
VCD-based activity, if supported
Vectorless activity estimation
```

## Stage 5A Blockers

Critical blockers remaining:

```text
Cadence Genus executable is not available in the current shell.
Official Cadence environment setup command is unknown.
Official competition 45 nm PDK is not confirmed.
Official Liberty/LEF/QRC paths are not confirmed.
Genus read/elaboration smoke tests cannot be run until Genus is available.
```
