# Changelog

## 2026-11-28

- Checked the shared-memory layout at all five barriers in Defrag. Rebuilding the logical thread index and one constant on resume brings the largest layout to 8,068 of 8,192 dwords, with 124 dwords available for scheduler and exchange state. The in-game pipeline check remains open.
- Captured the same two Cascading Shadows textures immediately before the target dispatch and before its follower on one RTX command list. The R8 plane and RGB channels of the RGBA8 texture matched at both points. The effect on the rendered scene remains open.
- Ran the alternating upload-gap test on the RTX 5060 Ti. It reached the opening prison window and stopped at the Windows memory reserve before the full comparison finished.

## 2026-11-27

- Compared changed-only and full buffer uploads on RTX 5060 Ti with Wide hashing. In the same stationary Series S scene, sampled card uploads fell from 107.5 to 46.2 MB per frame. Median frame time moved from 190 to 188 ms across five alternating phases per mode.
- Captured both Cascading Shadows textures at the same dispatch boundary on the RTX 5060 Ti with the shadow pass enabled and skipped. The scene differed between runs. The visual check is still open.

## 2026-11-26

- Verified a synthetic two-wave shared-memory test for Defrag on an RTX 5060 Ti. The in-game pipeline still fails. Confirmed another Cascading Shadows dispatch and recorded where its two output textures transition. The visual check is still open.
- Added the matched hash comparison to the README and updated the sustained gameplay target to 33.3 ms per frame.
- Reached the prison checkpoint on an RTX 5060 Ti with the Series S profile. The serial hash run measured 3.24 FPS, 304 ms median, and 330 ms p95 over 269 frames.
- Added an opt-in parallel GPU buffer hash. A separate wide-hash run with limited texture catch-up reached the bunks at 3.15 FPS over 60 seconds. The Windows memory guard ended the run. The camera and texture settings differed from the serial run.
- Reduced shader buffer windows to 1 MiB and shortened their tails. Wide mode measured 4.97 FPS, 195 ms median, and 226 ms p95 across 278 frames in a 60-second barred-window sample. This was a different runtime preset from the earlier runs. The run reached its 12-minute limit with no new NVIDIA driver errors and about 5.5 GiB of Windows commit headroom near the end.
- Repeated the 60-second barred-window sample in Serial mode on the same `780a22f` runtime, RTX 5060 Ti, and Series S preset. Serial measured 3.21 FPS, 306 ms median, and 348 ms p95 across 182 frame intervals. Neither window had shader pipeline creation. GPU send, hash, and compare averaged about 116 ms per frame in Serial and 11 ms in Wide.
- Added a configurable Windows window title. Verified that frame counter updates keep the configured title.
- Added a PowerShell helper for measuring frame intervals from diagnostic logs.
- Posted the source snapshot with its license and upstream credits. BCPack tables stay outside Git and are supplied at build time when needed.
- Made Loam public and added the generated progress page, benchmark history, resolver inventory, and README badge.
- Added generated tile maps and count badges to README Status. The registry audit includes ordinal bindings and corrects the Windows total to 149 entries. The GFX10 panel counts names in the public opcode tables.
- Reworked README Status to match AnyPS5's badge row and treemaps. The shader panels show which opcode values have names in Loam's GFX10 tables.
- Added short WASD pulses for offline diagnostics that respect input from a physical stick. Verified movement away from the barred window in the opening prison room.
- Recorded 3.28 FPS, 303 ms median, and 328 ms p95 across 170 intervals in a stationary 60-second window with the lower-memory preset. Four follow-up runs reached the Windows commit reserve. Windows logged no new NVIDIA driver or display-reset events during those runs.
- Verified Direct3D 12 GPU upload heaps on an RTX 5060 Ti. A 1.5 GiB upload budget measured 5.15 FPS and 194.36 ms mean frame time over a stationary 60-second window. The test kept rendering through movement before reaching the Windows memory reserve. A 2 GiB trial reached the same reserve as the scene loaded. Windows logged zero display-driver resets in both runs.
- Switched the shader status map to synthetic decoder probes. It now shows the 64-bit VOPC, VOP2, and VOP1 forms in VOP3 and lists recognized opcodes by family.
- Added DXIL translation for the VOP3 packed-byte average instruction, `v_lerp_u8`. Verified independent byte rounding on an RTX 5060 Ti and WARP.
- Fixed disassembly for the SMEM instructions `s_memtime`, `s_memrealtime`, and `s_get_waveid_in_workgroup`. They now print just their destination register.
- Replaced the headline status tiles with the GTA VI playability roadmap. Each tile records the evidence and its completion check. Opcode and resolver maps remain available in the source reference.
- Restored the dense status grid in the README, with separate work tiles for missing pipelines, VOP3, and SMEM. The smaller cells show individual checks.
- Restored the original library and GFX10 treemaps in README Status and documented what accounted for the pipeline skips.
- Put the remaining DXIL work inside the VOP3 and SMEM tiles and added a matching row for missing pipeline checks.
- Scoped the pipeline tiles to the observed RTX opening-room work and distinguished rejected shader signatures from per-frame skips.
- Rechecked pipeline failures on an RTX 5060 Ti with runtime `4e137e5`. The status generator can wrap longer local labels inside the same tile grid.
- Listed the four shader entry names tied to the verified RTX failures in the README status grid.
- Enabled wave32 translation for a single 64-lane compute wave when Loam can verify that the widened branches synchronize safely. The particle visibility shader passed DXIL validation and created its D3D12 pipeline on an RTX 5060 Ti in a standalone probe and a fresh Loam boot, where the game also bound the pipeline.
- Fixed descriptor tracking for memory accesses guarded by EXEC. The alpha prefilter now passes DXIL validation and creates its D3D12 pipeline on the RTX in a standalone probe and a fresh Loam boot.
- Kept verified shader checks in the README grid and gave them a green marker. Particle visibility and alpha prefilter passed their pipeline checks.
- Added an experimental Wave32 path that splits a guest workgroup into two host workgroups while preserving guest IDs. Direct and indirect compute dispatches expand X for this path. Enable it for a selected DXBC container with `VICTORY_VIRTUAL_WAVES=separate-groups` and `VICTORY_VIRTUAL_WAVES_DIGEST` set to the container's digest in hex.
- Validated and dispatched the cascading-shadow pipeline in the opening scene on an RTX 5060 Ti. The prison yard rendered with visual artifacts. Defrag remains open.
