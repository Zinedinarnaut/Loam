# Changelog

## 2026-11-26

- Reached the prison checkpoint on an RTX 5060 Ti with the Series S profile. The serial hash run measured 3.24 FPS, 304 ms median, and 330 ms p95 over 269 frames.
- Added an opt-in parallel GPU buffer hash. A separate wide-hash run with limited texture catch-up reached the bunks at 3.15 FPS over 60 seconds. The Windows memory guard ended the run. The camera and texture settings differed from the serial run.
- Reduced shader buffer windows to 1 MiB and shortened their tails. Wide mode measured 4.97 FPS, 195 ms median, and 226 ms p95 across 278 frames in a 60-second barred-window sample. This was a different runtime preset from the earlier runs.
- Added a configurable Windows window title. Verified that frame counter updates keep the configured title.
- Added a PowerShell helper for measuring frame intervals from diagnostic logs.
- Posted the source snapshot with its license and upstream credits. BCPack tables stay outside Git and are supplied at build time when needed.
