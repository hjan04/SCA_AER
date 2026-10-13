# Pre-integration safety manifest

Captured before replacing any existing tracked Stage 1 source file.

## Repository state

- Branch: `stage2/claude-architecture`
- HEAD: `5d271a4f02d6250732df8b87c1a345ebdc4b4af6`
- Git status snapshot: `README.md` was modified; 774 untracked entries were present. Those entries included the existing Stage 2 source/integration/server trees, Stage 2 audit documents and archives, and unrelated local submission/preparation files. There were no other tracked-path status entries.
- No files were staged by this integration.

## Collision hashes

All replacement sources are from `/home/hj/SCA_AER_model2_recovery` at source commit `1fbcb59`.

| Path | Current SHA-256 | Replacement source | Replacement SHA-256 |
|---|---|---|---|
| `rtl/adaptive/aer_adaptive_link_top.sv` | `ef1f72913350d25e38a47d10be0945925db8b71b468137e536ec6956f63eb52b` | recovery `rtl/adaptive/aer_adaptive_link_top.sv` | `4095f359bbf2459f5e844647382dc6e6a513ee627fc9e6683c6ed3947caada48` |
| `rtl/adaptive/aer_adaptive_top.sv` | `a7316f07023786b170057c3642aee6ba6ae3ab83ac82b57cb724037b4ffef33c` | recovery `rtl/adaptive/aer_adaptive_top.sv` | `8c7e71bc613d02d4dce95b5ec73fbaba60f779fb79557c5a7e89f371b31c03b1` |
| `rtl/adaptive/aer_block_occupancy.sv` | `7eba46cd46baa0db05369415d1c4b3702d32fd0ac7441800180b614774856108` | recovery `rtl/adaptive/aer_block_occupancy.sv` | `cd064599f16eb9ee4f39f01d13e5a925add19950a3bd57660b7e7d18dfa11e4b` |
| `rtl/adaptive/aer_mode_controller.sv` | `c042b7bf412824fe4de90a537154c5e6b4c46b17dd3feedb59b56e1dbcad5f5c` | recovery `rtl/adaptive/aer_mode_controller.sv` | `3439b4aa3219eb505aca6643c0a5a41c4cdd15c6e74ef42fff4f1e6ca0ff93b1` |
| `tb/tests/tb_adaptive_directed.sv` | `f1848163d08c4dfedcfcca1e6abea289a826ba32675a37fab77bf37c346ce267` | recovery `tb/tests/tb_adaptive_directed.sv` | `5239345913e91a3ef557a4e19dc6a9a7a0791a1ace1f837cf5111d432a7569a2` |
| `tb/tests/tb_adaptive_link_directed.sv` | `71cdf922e274c9a1c25761df49a9a37e7fad82c819c1f34e0fbf6d5e83d236d9` | recovery `tb/tests/tb_adaptive_link_directed.sv` | `423f29f0a2bf1a555bf80e18cc24c5fce0f21288dbbb142453428b9dc9f946a1` |

## Diff classification recorded before promotion

- RTL files differing from main: the four listed above.
- Test files differing from main: the two listed above.
- New recovery test: `tb/tests/tb_mode_hysteresis_directed.sv`.
- `rtl/adaptive/aer_dense_block_selector.sv` is unchanged between main and recovery.
- Recovery-only reproduction scripts and compact evidence are additions; they do not replace the main baseline/Stage 3/Stage 4 flows.
- Recovery-only Python cache files are disposable and excluded.
