# Ghostty Blackhole

![Ghostty Blackhole demo](demo.gif)

A black hole floating inside your [Ghostty](https://ghostty.org) terminal —
and a pomodoro break reminder in disguise. It starts small, grows as the
hour progresses, and demands a break by swallowing ever more of your screen.
Take the break and it leaves you alone.

Inspired by [Eric Bruneton's black hole shader](https://ebruneton.github.io/black_hole_shader/),
which beam-traces Schwarzschild geodesics against precomputed lookup tables.
A Ghostty custom shader is a single Shadertoy-style fragment pass over the
terminal texture, so this project approximates the same visual physics in
screen space — with your terminal contents playing the role of the lensed
background sky.

## What it renders

- **Gravitational lensing** — weak-field deflection (`α = θ_E²/r`) warps the
  terminal text around the hole; inside the Einstein radius the mapping
  flips, giving the mirrored secondary image of a real lens. Blue is bent
  slightly more than red for a touch of chromatic aberration.
- **Event horizon** — a hard shadow disc that text fades into.
- **Photon ring** — thin hot ring just outside the horizon.
- **Accretion disk** — tilted near-edge-on disk with Keplerian shear (inner
  streaks orbit faster), doppler beaming (approaching side bright and
  blue-white, receding side dim orange-red), and a faint circular halo
  standing in for the lensed image of the disk's far side.
- The hole drifts on a slow Lissajous path, confined to the upper part of
  the screen — the bottom `WORK_AREA` fraction (your prompt) is never
  distorted. Drift speed and reach follow its size: small and calm, big
  and restless.

## Pomodoro mode

The break reminder is computed entirely inside the shader — no daemon, no
shell hooks, nothing outside `blackhole.glsl`.

Shaders are stateless (no buffers persist between frames, and Ghostty has no
custom uniforms), so a shader cannot remember when *your* work streak began.
Instead the schedule is anchored to the wall clock via `iDate`:

- **Cycle**: the hole is always present while you work — it starts small at
  the cycle floor, grows over `WORK_PERIOD_MIN` (default 55 min), collapses
  back to small in the last minute, and stays small through `BREAK_MIN`
  (default 5 min). With 55+5 the peak hits at five-to-the-hour — a fixed,
  predictable rhythm.
- **Typing detector**: `iTimeCursorChange` tracks cursor activity in your
  terminal. Stop using it for `IDLE_FADE_SEC` (default 90 s) and the hole
  shrinks live, gone entirely after a few minutes of quiet — it never nags
  while you aren't actually working.

The trade-off of self-containment: the cycle won't re-anchor to a break you
take at an odd time — it's an hourly bell, not a per-streak stopwatch.

## Install

Requires Ghostty 1.3+ (for the cursor and clock shader uniforms).

Clone the repo, then add to your Ghostty config (`~/.config/ghostty/config`
or `~/Library/Application Support/com.mitchellh.ghostty/config` on macOS):

```ini
custom-shader = /path/to/blackhole_ghostty/blackhole.glsl
custom-shader-animation = true
```

Reload the config (`cmd+shift+,` on macOS) or open a new window.

## Tuning

Constants at the top of `blackhole.glsl`:

| Constant          | Effect                                                  |
|-------------------|---------------------------------------------------------|
| `HOLE_RADIUS`     | Event horizon size at full intensity (fraction of screen height) |
| `LENS_STRENGTH`   | Einstein radius at full intensity — how far text bends  |
| `DISK_GAIN`       | Accretion disk brightness                               |
| `DRIFT_SPEED`     | How fast the hole floats around                         |
| `DISK_TILT`       | Disk tilt in radians                                    |
| `WORK_AREA`       | Bottom screen fraction kept completely undistorted      |
| `WORK_PERIOD_MIN` | Work minutes per pomodoro cycle (growth phase)          |
| `BREAK_MIN`       | Break minutes per cycle (hole stays small)              |
| `IDLE_FADE_SEC`   | Typing pause after which the hole starts to fade        |

Edit and reload (`cmd+shift+,`), or use the bundled `tune.py` for
interactive keyboard tuning with instant hot reload.

The period knobs accept fractional minutes, which makes a fast debug loop:
set `WORK_PERIOD_MIN = 0.33` and `BREAK_MIN = 0.08` to watch a complete
pomodoro cycle — growth, collapse, break — in about 25 seconds.

## Uniforms Ghostty gives custom shaders (1.3)

`iResolution`, `iTime`, `iTimeDelta`, `iFrameRate`, `iFrame`, `iMouse`
(unused), `iDate` (wall clock), `iChannel0` (the terminal, `iChannel1-3`
unused), `iCurrentCursor`/`iPreviousCursor` (xy position, zw size),
`iCurrentCursorColor`/`iPreviousCursorColor`, `iCurrentCursorStyle`/
`iPreviousCursorStyle`, `iCursorVisible`, `iTimeCursorChange`, `iFocus`,
`iTimeFocus`, `iPalette[256]`, `iBackgroundColor`, `iForegroundColor`,
`iCursorColor`, `iCursorText`, `iSelectionForegroundColor`,
`iSelectionBackgroundColor`. No persistent buffers between frames — shaders
are stateless, which is why the pomodoro is wall-clock-anchored.

Two gotchas worth knowing if you hack on this:

- Ghostty's `fragCoord` y-axis runs **top-down**, opposite of the Shadertoy
  convention it otherwise follows.
- To trigger a config reload from a script, send `SIGUSR2` — but find the
  PID with `ps`, not `pgrep`/`pkill`: those silently exclude their own
  ancestors, and Ghostty is an ancestor of any shell running inside it.

## License

MIT — see [LICENSE](LICENSE).

Inspired by [Eric Bruneton's black hole shader](https://github.com/ebruneton/black_hole_shader)
(BSD-3-Clause). No code from that project is used here — this shader is an
independent screen-space approximation written from scratch; the credit is
for the idea and the physics it demonstrates.
