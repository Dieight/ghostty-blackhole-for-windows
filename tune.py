#!/usr/bin/env python3
"""Live tuner for blackhole.glsl — run it inside Ghostty.

Parses the `const float NAME = VALUE;` block at the top of the shader,
lets you nudge values with the keyboard, rewrites the file and triggers
a Ghostty config reload (cmd+shift+,) so the shader hot-reloads.

Keys:
  up/down or k/j   select parameter
  left/right h/l   nudge value by step
  shift + h/l      nudge by 10x step
  s                type an exact value
  r                force a reload
  q / ctrl-c       quit
"""

import math
import os
import re
import signal
import subprocess
import sys
import termios
import tty

SHADER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blackhole.glsl")
CONST_RE = re.compile(
    r"^(const float\s+)(\w+)(\s*=\s*)(-?\d+\.\d+)(\s*;.*)$"
)


def load():
    params = []  # (name, value, line_index)
    with open(SHADER) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        m = CONST_RE.match(line)
        if m:
            params.append([m.group(2), float(m.group(4)), i])
    return lines, params


def save(lines, params):
    for name, value, i in params:
        lines[i] = CONST_RE.sub(
            lambda m: f"{m.group(1)}{m.group(2)}{m.group(3)}{value:.4f}{m.group(5)}",
            lines[i],
        )
    tmp = SHADER + ".tmp"
    with open(tmp, "w") as f:
        f.writelines(lines)
    os.replace(tmp, SHADER)


def reload_ghostty():
    # Ghostty (>= 1.2) reloads its config — including custom shaders — on
    # SIGUSR2. No focus or Accessibility permission needed. PIDs come from ps,
    # not pgrep/pkill: those silently exclude their own ancestors, and Ghostty
    # is an ancestor of the shell this tuner runs in.
    out = subprocess.run(["ps", "-axco", "pid,comm"],
                         capture_output=True, text=True).stdout
    ok = False
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].strip() == "ghostty":
            try:
                os.kill(int(parts[0]), signal.SIGUSR2)
                ok = True
            except OSError:
                pass
    return ok, "" if ok else "is Ghostty running?"


def step_for(value):
    if value == 0.0:
        return 0.01
    return 10.0 ** (math.floor(math.log10(abs(value))) - 1)


def read_key():
    ch = sys.stdin.read(1)
    if ch == "\x1b":  # arrow keys
        seq = sys.stdin.read(2)
        return {"[A": "up", "[B": "down", "[C": "right", "[D": "left"}.get(seq, "")
    return ch


def draw(params, sel, status):
    sys.stdout.write("\x1b[2J\x1b[H")
    print("black hole tuner — j/k select, h/l nudge, H/L coarse, s set, r reload, q quit\n")
    for i, (name, value, _) in enumerate(params):
        cursor = "\x1b[7m" if i == sel else ""
        print(f"  {cursor}{name:<16} {value:>10.4f}\x1b[0m   step {step_for(value):g}")
    print(f"\n  {status}")
    sys.stdout.flush()


def prompt_value(fd, old_settings):
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    try:
        raw = input("\n  new value: ")
        return float(raw)
    except ValueError:
        return None
    finally:
        tty.setcbreak(fd)


def main():
    lines, params = load()
    if not params:
        sys.exit(f"no `const float` params found in {SHADER}")
    sel, status = 0, f"{len(params)} params from {os.path.basename(SHADER)}"

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    try:
        while True:
            draw(params, sel, status)
            key = read_key()
            changed = False
            if key in ("q", "\x03"):
                break
            elif key in ("k", "up"):
                sel = (sel - 1) % len(params)
            elif key in ("j", "down"):
                sel = (sel + 1) % len(params)
            elif key in ("h", "l", "H", "L", "left", "right"):
                direction = 1 if key in ("l", "L", "right") else -1
                coarse = 10.0 if key in ("H", "L") else 1.0
                params[sel][1] += direction * coarse * step_for(params[sel][1])
                params[sel][1] = round(params[sel][1], 6)
                changed = True
            elif key == "s":
                v = prompt_value(fd, old_settings)
                if v is not None:
                    params[sel][1] = v
                    changed = True
            elif key == "r":
                changed = True

            if changed:
                save(lines, params)
                ok, err = reload_ghostty()
                status = (
                    f"saved {params[sel][0]} = {params[sel][1]:.4f}, reloaded"
                    if ok else
                    f"saved, but reload failed ({err or 'grant Accessibility to Ghostty'}) "
                    f"— press cmd+shift+, manually"
                )
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        print()


if __name__ == "__main__":
    main()
