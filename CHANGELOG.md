# Changelog

## 2026-11-26

- Reached the prison checkpoint on an RTX 5060 Ti with the Series S profile. The serial hash run measured 3.24 FPS, 304 ms median, and 330 ms p95 over 269 frames.
- Added an opt-in parallel GPU buffer hash. A separate wide-hash run with limited texture catch-up reached the bunks at 3.15 FPS over 60 seconds. The Windows memory guard ended the run. The camera and texture settings differed from the serial run.
- Reduced shader buffer windows to 1 MiB and shortened their tails. Wide mode measured 4.97 FPS, 195 ms median, and 226 ms p95 across 278 frames in a 60-second barred-window sample. This was a different runtime preset from the earlier runs. The run reached its 12-minute limit with no new NVIDIA driver errors and about 5.5 GiB of Windows commit headroom near the end.
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
