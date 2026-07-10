<p align="center">
  <a href="README.md">English</a> | <a href="README.zh.md">Chinese</a>
</p>

# Ghostty Blackhole - Windows Terminal Port

![Ghostty Blackhole demo](demo.gif)

A ray-traced black hole inside Windows Terminal. This fork ports the original
[ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole) to Windows
Terminal's HLSL pixel-shader interface while preserving the Ghostty GLSL files.

The Windows port now includes two stable size modes: Codex context tracking and
a fixed-size shader. The earlier Windows Terminal pomodoro implementation is
kept as an experimental legacy version because Terminal's shader `Time` value
can reset or jump.

## Windows Terminal versions

| File | Behavior | Helper required | Recommended use |
|------|----------|-----------------|-----------------|
| `blackhole.hlsl` | Grows as the active Codex context window fills | `tools/Watch-CodexContext.ps1` | Default context mode |
| `blackhole.fixed.hlsl` | Constant at about 80% of the configured maximum size | No | Stable always-on effect |
| `blackhole.pomodoro.hlsl` | Legacy timer-driven growth and rest cycle | Optional legacy helper | Testing only |

`blackhole.glsl` remains the original Ghostty shader with its Ghostty-specific
pomodoro, token, and demo modes.

## Features

- Ray-traced black hole shadow and photon ring
- Gravitational lensing of terminal contents
- Relativistic accretion disk with Doppler beaming
- Codex context-window tracking on Windows Terminal
- Fixed-size Windows Terminal version with no background helper
- 42-second demo mode in the HLSL source

## Quick start: fixed version

Point Windows Terminal directly at `blackhole.fixed.hlsl`:

```json
"profiles": {
    "defaults": {
        "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.fixed.hlsl"
    }
}
```

Save the settings, then run **Toggle terminal visual effects** from the command
palette. The black hole stays at `FIXED_SIZE_RATIO` (default `0.8`) of the
configured maximum. Its size stays constant while the black hole follows the
same free-moving path as the other versions; disk matter continues to animate.

## Quick start: Codex context version

The shader cannot read Codex state directly. The helper watches Codex session
logs, writes the current context fill into generated HLSL files under
`%USERPROFILE%\.terminal`, and switches `experimental.pixelShaderPath` between
those files so Windows Terminal reloads the value.

First make sure the profile defaults already contain the setting (the helper
updates an existing property; it does not insert a missing one):

```json
"profiles": {
    "defaults": {
        "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.hlsl"
    }
}
```

Open PowerShell in the repository root:

```powershell
cd C:\path\to\ghostty-blackhole-for-windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Watch-CodexContext.ps1 -Status
```

The relative `-File` path only works from the repository root. From any other
directory, use the full script path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\ghostty-blackhole-for-windows\tools\Watch-CodexContext.ps1" -Status
```

Keep that PowerShell process running while using Codex. It is silent unless
`-Status` is supplied. Stop it with `Ctrl+C`; by default it restores the shader
path that was active before startup.

Useful options:

| Option | Effect |
|--------|--------|
| `-Status` | Print session id, token use, context fill, and generated file |
| `-Once` | Read and generate once, then exit |
| `-NoSettingsUpdate` | Generate HLSL without editing Terminal settings |
| `-NoRestoreOnExit` | Leave the generated shader selected after exit |
| `-TemplatePath` | Use another context-mode HLSL template |
| `-OutputDirectory` | Change where generated shaders are written |

The helper reads the latest `token_count` event and uses `total_tokens /
model_context_window`, clamped to 0-100%. Cached input is already included in
Codex's token totals and is not counted twice.

## Tuning

Edit constants near the top of the selected HLSL file, then reload the shader.

| Constant | Effect |
|----------|--------|
| `HOLE_RADIUS` | Base shadow radius |
| `MAX_SIZE_SCALE` | Full context-mode size multiplier (default `1.3`) |
| `FIXED_SIZE_RATIO` | Fixed version's fraction of maximum (default `0.8`) |
| `CONTEXT_GROW_EASE` | Context-mode growth curve |
| `CONTEXT_DEBUG_BAR` | Optional context fill diagnostic at the top of the screen (off by default) |
| `WORK_AREA` | Bottom fraction protected from distortion |
| `N_STEPS` | Per-pixel geodesic integration budget; main performance dial |

## Validation

Compile any Windows Terminal shader locally with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-HlslCompile.ps1 -Path .\blackhole.hlsl
```

Replace the path with `blackhole.fixed.hlsl` or
`blackhole.pomodoro.hlsl` to test another version.

## Ghostty

Requires Ghostty 1.3+. Add this to `~/.config/ghostty/config`:

```ini
custom-shader = /path/to/blackhole.glsl
custom-shader-animation = true
```

`claude-token.py` is the existing Ghostty token-mode helper. It is independent
of the Windows Terminal context helper.

## Files

| File | Description |
|------|-------------|
| `blackhole.hlsl` | Windows Terminal context-mode template |
| `blackhole.fixed.hlsl` | Windows Terminal fixed 0.8x version |
| `blackhole.pomodoro.hlsl` | Legacy experimental Windows timer version |
| `tools/Watch-CodexContext.ps1` | Codex context watcher and shader generator |
| `tools/Start-PomodoroHelper.ps1` | Optional helper for the legacy pomodoro shader |
| `tools/Test-HlslCompile.ps1` | Local HLSL compile check |
| `blackhole.glsl` | Original Ghostty shader |
| `claude-token.py` | Ghostty token-mode helper |

## License

MIT - see [LICENSE](LICENSE).

Inspired by [Eric Bruneton's black hole shader](https://github.com/ebruneton/black_hole_shader)
(BSD-3-Clause). The shader is an independent screen-space approximation.
