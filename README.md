<p align="center">
  <a href="README.md">🇬🇧 English</a> | <a href="README.zh.md">🇨🇳 中文</a>
</p>

# Ghostty Blackhole — Windows Terminal Port

![Ghostty Blackhole demo](demo.gif)

A ray-traced black hole inside your terminal — now on **Windows Terminal**.

This fork ports the original [ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole)
to Windows Terminal's HLSL pixel shader interface, while keeping the original
Ghostty GLSL shader intact.

The black hole integrates null geodesics through the Schwarzschild metric in
real time — every pixel near the hole traces its own photon path. Your terminal
contents play the role of the lensed background sky.

## Features

- **Ray-traced black hole shadow** — photons under `b_crit` spiral through the
  horizon; text behind the hole really is gone
- **Gravitational lensing** — text bends, magnifies, and mirrors inside the
  Einstein ring; seamless handoff to weak-field deflection far from the hole
- **Accretion disk** — Shakura–Sunyaev temperature profile, relativistic Doppler
  beaming, Keplerian orbital streaks; the Interstellar look
- **Photon ring** — emergent from rays winding near the `1.5 r_s` photon sphere
- **Gravitational time dilation** — inner orbits visibly freeze as the hole
  grows
- **Pomodoro mode** — hole grows over `WORK_PERIOD_MIN` (default 45 min),
  collapses for `BREAK_MIN` (default 5 min)
- **Demo mode** — 42 s self-running showcase loop cycling through disk presets

## Supported platforms

| Platform | File | Status |
|----------|------|--------|
| **Windows Terminal** (Windows 10 22H2+, Windows 11) | `blackhole.hlsl` | ✅ Full support (pomodoro + demo) |
| **Ghostty** (macOS, Linux) | `blackhole.glsl` | ✅ Full support (pomodoro + token + demo) |

> **Token mode** (Claude Code context-window tracking) is Ghostty-only —
> Windows Terminal shaders lack the cursor-color uniforms it requires.

## Quick start (Windows Terminal)

1. Clone this repo and note the path to `blackhole.hlsl`.

2. Edit Windows Terminal `settings.json` (`Ctrl+,` → "Open JSON file") and add
   to your profile's `defaults`:

   ```json
   "profiles": {
       "defaults": {
           "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.hlsl"
       }
   }
   ```

3. Save, then press `Ctrl+Shift+P` → **"Toggle terminal visual effects"**.
   Or bind a key in `actions`:

   ```json
   { "command": "toggleShaderEffects", "keys": "ctrl+shift+b" }
   ```

## Quick start (Ghostty)

Requires Ghostty 1.3+. Add to `~/.config/ghostty/config`:

```ini
custom-shader = /path/to/blackhole.glsl
custom-shader-animation = true
```

Reload (`cmd+shift+,`) or open a new window.

## Pomodoro mode

The hole is always present while you work — it starts small, grows over
`WORK_PERIOD_MIN` (default 45 min), collapses in the last minute, and stays
small through `BREAK_MIN` (default 5 min). On Ghostty the schedule anchors to
the wall clock; on Windows Terminal it runs from `Time` (seconds since the
shader was enabled).

## Size modes

Set `SIZE_MODE` at the top of `blackhole.glsl` / `blackhole.hlsl`:

- **`MODE_POMODORO`** *(default)* — self-contained pomodoro timer
- **`MODE_DEMO`** — 42 s showcase loop; useful for recording and testing
- **`MODE_TOKENS`** — Ghostty only; tracks Claude Code context-window fill

### Demo mode

The hole grows from seed to full size over 40 s while the disk look tours
8 presets (Inferno → Gargantua → M87\* donut → Face-on ember → Quasar →
Blazar → Pure lens → Inferno), crossfading every ~5 s.

## Tuning

Edit constants at the top of the shader file, then reload the shader.

| Constant | Effect |
|----------|--------|
| `HOLE_RADIUS` | Shadow radius at full size (fraction of screen height) |
| `LENS_DEPTH` | Lens strength — bigger = text bends harder |
| `STAR_GAIN` | Starfield brightness (0 = off) |
| `DISK_INNER` / `DISK_OUTER` | Disk inner/outer edge in `r_s` |
| `DISK_INCL` / `DISK_ROLL` | Disk inclination and rotation (radians) |
| `DISK_TEMP` | Blackbody temperature of hottest annulus (Kelvin) |
| `DISK_GAIN` / `DISK_OPACITY` | Disk brightness and opacity |
| `DOPPLER_MIX` / `DISK_BEAM` | Relativistic color/beaming strength |
| `DISK_SPEED` / `DISK_WIND` / `DISK_CONTRAST` | Orbital streaks |
| `EXPOSURE` | Disk light tonemap exposure |
| `DRIFT_SPEED` | How fast the hole floats |
| `WORK_AREA` | Bottom screen fraction kept undistorted |
| `DILATION_MIN` | Time dilation at full size |
| `WORK_PERIOD_MIN` | Pomodoro work phase (minutes) |
| `BREAK_MIN` | Pomodoro break phase (minutes) |
| `TIME_SCALE` | Testing: >1 fast-forwards (e.g. 100 = 27 s cycle) |

`N_STEPS` (a `#define`) sets the geodesic integration budget per pixel —
the main performance dial. Lower it if the terminal gets sluggish.

## Files

| File | Description |
|------|-------------|
| `blackhole.glsl` | Original Ghostty shader (GLSL, all modes) |
| `blackhole.hlsl` | Windows Terminal shader (HLSL, pomodoro + demo) |
| `claude-token.py` | Token-mode helper for Claude Code (Ghostty only) |
| `tuner/` | macOS SwiftUI tuning app (Ghostty only) |

## License

MIT — see [LICENSE](LICENSE).

Inspired by [Eric Bruneton's black hole shader](https://github.com/ebruneton/black_hole_shader)
(BSD-3-Clause). The shader is an independent screen-space approximation written
from scratch.
