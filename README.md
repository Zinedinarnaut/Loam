# Loam

Loam is an experimental Xbox Series compatibility layer for Windows. It boots the menus and renders the opening prison sequence on an RTX 5060 Ti. The scene still has rendering glitches, and Windows memory pressure can end a run.

## Build

Use Windows x64, a CPU with AVX2, and the Rust toolchain pinned in this repo. Rendering needs a Direct3D 12 GPU with Shader Model 6.6. The world also uses mesh shaders.

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
Copy-Item victory.example.toml victory.toml
.\target\diag\victory.exe config
```

Set your paths in `victory.toml`. Keep title files and caches outside the checkout. For BCPack decoding, set `LOAM_BCPACK_TABLES` to the path of a table file you are authorized to use, then build. Without the tables, the source still builds and BCPack requests fail with an error.

Runtime options and upstream build details are in [the inherited notes](UPSTREAM.md).

## Frame timings

```powershell
.\scripts\Measure-FrameTime.ps1 -LogPath .\boot.log -AnchorTimestamp '2026-11-25T23:06:51Z' -DurationSeconds 60
```

Use a timestamp from your own log. Pick a stationary view after pipeline creation settles. The script reads individual frame intervals and prints mean FPS, median, and p95. Keep the camera, settings, and capture cadence the same when comparing runs.

The [changelog](CHANGELOG.md) records tested milestones and known failures. The [asset policy](docs/asset-policy.md) covers what belongs in this repo.

## Credits

Loam is based on the GPL-3.0-or-later work of Marvisak, fxceless, and their contributors. This repository began from the locally tested `780a22f` source snapshot. Build inputs stay on the user's machine. [License](LICENSE) · [Upstream notes and credits](UPSTREAM.md)
