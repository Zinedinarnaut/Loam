# Loam

An attempt to run GTA VI on PC.

Loam is a Windows compatibility layer for Xbox Series software. It runs the game's x86-64 code on the host, supplies the console APIs it calls, and translates its GPU work for Direct3D 12.

[![Loam frame-rate progress](https://zinedinarnaut.github.io/Loam/fps.svg)](https://zinedinarnaut.github.io/Loam/progress.html)

[Progress](https://zinedinarnaut.github.io/Loam/progress.html) · [Changelog](CHANGELOG.md) · [Architecture](docs/architecture.md) · [Asset policy](docs/asset-policy.md)

## Status

| Stage | Result |
| --- | --- |
| Boot and menus | The title starts. Menu input works in the offline test setup. |
| Checkpoint | A saved prison checkpoint loads. |
| Opening scene | The prison interior and exterior render with lighting and texture glitches. |
| Gameplay controls | Movement in the first mission still needs verification. |
| Performance | 4.97 FPS in the prison doorway on an RTX 5060 Ti. |

That run used the Series S profile at 1080p. In a 60-second window, 278 frame intervals gave a 195 ms median and 226 ms p95. The run reached its 12-minute limit with zero new NVIDIA driver errors.

The current goal is sustained 33 FPS in controllable gameplay. Earlier tests reached the Windows memory reserve. The [progress page](https://zinedinarnaut.github.io/Loam/progress.html) records each run with its scene, settings, and outcome.

## Build and run

Windows x64, an AVX2 CPU, and the pinned Rust toolchain are required. Rendering uses a Direct3D 12 GPU with Shader Model 6.6 and mesh shaders.

For BCPack decoding, set `LOAM_BCPACK_TABLES` to a local table file you are authorized to use before building. Source checks and synthetic tests can run without it.

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
Copy-Item victory.example.toml victory.toml
.\target\diag\victory.exe config
```

Edit `victory.toml` to point to your own title files outside the checkout. The runtime can inspect or launch the supplied executable.

```powershell
.\target\diag\victory.exe inspect 'D:\title\game.exe'
.\target\diag\victory.exe run 'D:\title\game.exe' --execute --console series-s
```

## Measure a run

Choose a fixed camera after pipeline compilation settles. Use the same settings and capture cadence for both runs.

```powershell
.\scripts\Measure-FrameTime.ps1 -LogPath .\boot.log -AnchorTimestamp '2026-11-25T23:36:08Z' -DurationSeconds 60
```

The progress site is generated from [the recorded results](site/progress.json). The [inherited runtime notes](UPSTREAM.md) cover implementation details and debug switches.

## Credits

Loam starts from the work of Marvisak, fxceless, and contributors. [VIctory](https://github.com/Marvisak/VIctory) · [fxceless fork](https://github.com/fxceless/victory-fork) · [GPL-3.0-or-later](LICENSE)
