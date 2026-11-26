# Loam

An attempt to run GTA VI on PC.

Loam is a Windows compatibility layer for Xbox Series software. It runs the game's x86-64 code on the host, supplies the console APIs it calls, and translates its GPU work for Direct3D 12.

[Build and run](#build-and-run) · [Benchmarks](#benchmarks) · [Progress](https://zinedinarnaut.github.io/Loam/progress.html) · [Changelog](CHANGELOG.md) · [Architecture](docs/architecture.md) · [Asset policy](docs/asset-policy.md)

## Status

[![Windows memory status](https://zinedinarnaut.github.io/Loam/windows-memory.svg)](https://zinedinarnaut.github.io/Loam/progress.html#task-windows-memory) [![Opening mission status](https://zinedinarnaut.github.io/Loam/mission-completion.svg)](https://zinedinarnaut.github.io/Loam/progress.html#task-mission-completion) [![Gameplay FPS target](https://zinedinarnaut.github.io/Loam/fps-target.svg)](https://zinedinarnaut.github.io/Loam/progress.html#task-frame-rate)

[![Loam playability roadmap](https://zinedinarnaut.github.io/Loam/status-map.svg?v=4)](https://zinedinarnaut.github.io/Loam/progress.html#status-map)

The menu, opening checkpoint, and scripted movement are verified. Windows memory is the first blocker to finishing the mission. The fastest measured stationary sample was 5.15 FPS on an RTX 5060 Ti. The goal is sustained gameplay at 33 FPS.

[Tile evidence and completion checks](https://zinedinarnaut.github.io/Loam/progress.html#roadmap-details) · [Shader opcode reference](https://zinedinarnaut.github.io/Loam/progress.html#shader-opcodes) · [Windows API registry](https://zinedinarnaut.github.io/Loam/progress.html#registry)

## Benchmarks

| Opening prison scene | FPS | Median frame time | P95 frame time | Intervals |
| --- | ---: | ---: | ---: | ---: |
| Barred-window view, 1.5 GiB GPU upload budget | **5.15** | 192 ms | 218 ms | 262 |
| Barred-window view, reduced shader buffer windows | 4.97 | 195 ms | 226 ms | 278 |
| Barred-window view, lower-memory preset | 3.28 | 303 ms | 328 ms | 170 |
| Doorway view, serial hash | 3.24 | 304 ms | 330 ms | 269 |
| Bunks view, wide hash with limited texture catch-up | 3.15 | 328 ms | 360 ms | 178 |

The barred-window samples used an RTX 5060 Ti and the Series S profile. The GPU upload run averaged 194.36 ms per frame in a 60-second stationary window. It rendered the room after movement, then reached the Windows memory reserve. Camera views, runtime settings, and background load varied across runs. [Full results](https://zinedinarnaut.github.io/Loam/progress.html#benchmark) · [Benchmark data](site/progress.json)

## Build and run

### Requirements

- **Build on Windows 10 or 11 (x64).** Install Git, Rust via [rustup](https://rustup.rs/), and the **Desktop development with C++** workload with the Windows SDK. [Microsoft C++ Build Tools](https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line)
- **To run a title,** you need an AVX2 CPU, a Direct3D 12 GPU with Shader Model 6.6 and mesh shaders, and your own Xbox Series title files.

### 1. Build Loam

Open PowerShell and run the following. If you already cloned Loam, start with `rustup toolchain install` from the repository folder.

```powershell
git clone https://github.com/Zinedinarnaut/Loam.git
Set-Location Loam
rustup toolchain install
cargo build --locked --release -p victory
```

The build produces `target\release\victory.exe`, Loam's command-line tool.

For BCPack texture decoding, set `$env:LOAM_BCPACK_TABLES` to the path of a local table file you’re authorized to use, then run the build command again. Keep the file outside the checkout. [Asset policy](docs/asset-policy.md#local-bcpack-tables)

### 2. Check your title executable

Replace the example path with your own Xbox Series executable. Keep it alongside its title files in a folder outside the checkout. The `inspect` command reads the executable and prints its details.

```powershell
$titleExe = 'D:\XboxTitles\Example\Game.exe'
.\target\release\victory.exe inspect $titleExe
```

### 3. Run the title

```powershell
.\target\release\victory.exe run $titleExe --execute --console series-s
```

`--execute` starts the title. `--console series-s` selects the profile used for the benchmark above. The default profile is Series X.

Loam defaults to `%LOCALAPPDATA%\victory\cache` for generated files and `%LOCALAPPDATA%\victory\data` for saves and crash logs. To change those locations, use [victory.example.toml](victory.example.toml) as the template for `victory.toml` and run `.\target\release\victory.exe config` to check the paths.

### Record a benchmark

In PowerShell 7, enable frame logging and run the same scene with a fixed camera. Keep the settings and camera view consistent when comparing runs.

```powershell
$env:VICTORY_FRAME_LOG = '1'
$env:VICTORY_LOG = 'info'
$logPath = Join-Path $env:TEMP "loam-$(Get-Date -Format yyyyMMdd-HHmmss).log"
.\target\release\victory.exe run $titleExe --execute --console series-s 2>&1 |
    Tee-Object -FilePath $logPath
```

After the run, find a `frame times:` line when the camera was steady. Copy its timestamp, including the `Z` or UTC offset, and choose a point with at least 60 seconds of log after it.

```powershell
$start = Read-Host 'Timestamp at the start of the benchmark'
.\scripts\Measure-FrameTime.ps1 -LogPath $logPath -AnchorTimestamp $start -DurationSeconds 60
```

[Runtime notes and debug options](UPSTREAM.md)

## Credits

Loam starts from the work of Marvisak, fxceless, and contributors. [VIctory](https://github.com/Marvisak/VIctory) · [fxceless fork](https://github.com/fxceless/victory-fork) · [GPL-3.0-or-later](LICENSE)
