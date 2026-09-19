# LazRandR — history

## 2021: the virtual-display idea

The goal was to split one large monitor into several virtual displays, so that
windows would snap and maximise into regions as if each were its own screen.
XRandR 1.5 added `xrandr --setmonitor`, which defines "monitors" that don't
have to match physical outputs, and LazRandR began as a Lazarus GUI around it.

| Date | Commit | |
|---|---|---|
| 2021-11-27 | `d97fd8c`, `9a83b15` | Initial commits |
| 2021-11-27 | `889d46a` | "total mess" — first working experiments |
| 2021-11-28 | `ec9588d` | Functional display layout editor |
| 2021-11-29 | `9dc2c1a` | Fixes so it would also run on Windows |

The layout editor worked, and the split commands were generated correctly. But
the desktop environments that matter — Cinnamon, GNOME, MATE, Budgie, Unity —
ignore XRandR monitors when snapping and maximising windows. There was no
longer a layer underneath that would honour them, so the core feature had to
be gated off on exactly the desktops it was meant for. The project stalled.

## 2026: the touchscreen

A small portable touchscreen, plugged in alongside two 4K monitors on Linux
Mint, displayed perfectly — and touching it moved the pointer on a different
monitor. X maps an absolute input device across the entire virtual desktop,
and neither Cinnamon's display panel nor any other exposes the one setting
that fixes it: the device's *Coordinate Transformation Matrix*.

Doing it by hand with `xinput set-prop` works until the next logout, the next
rotation, or the next time the layout changes. What was needed was a layout
tool that understood input devices, so the old editor was rebuilt around that.

| Date | Commit | |
|---|---|---|
| 2026-09-11 | `52f28e6` | Rewrite as a display + touch mapping tool; virtual splits removed |
| 2026-09-11 | `cdbbdc8` | Stronger snapping, stable zoom, hotplug detection, device toggle |
| 2026-09-11 | `e5e9c1b` | Inactive screens parked in a tray |
| 2026-09-11 | `5e24f91` | Warn before a layout the X screen cannot grow to fit |
| 2026-09-11 | `ee498af` | Confirm-or-revert on apply, optimised build |
| 2026-09-11 | `289c4c8` | Correct layout extent; framebuffer is never shrunk after growth is refused |
| 2026-09-11 | `857e3e0` | Scaling split into honest controls; muffin fractional scaling |
| 2026-09-11 | `4e899a1` | Layout persisted into the login manager, not just the session |

## Lessons along the way

- **Touch needs its own matrix.** Placement on the desktop and the input
  mapping are separate settings; both must be applied and both must be
  persisted, and the matrix has to compose the output's rotation.
- **Cinnamon forgets `xrandr` layouts.** Only changes made through its own
  panel are written to `monitors.xml`, so LazRandR writes its own replay
  script and autostart entry.
- **The login screen is a race.** X sizes its screen from whichever outputs
  finished their handshake in time; a monitor that wakes 1.7 s late gets placed
  at `+0+0` and mirrored. The only fix is the display manager's own setup
  hook, which LazRandR now installs.
- **Say what a control really does.** Cinnamon's interface scale is integer
  only; fractional values were being smuggled into text scaling. They are now
  separate, clearly labelled controls.
