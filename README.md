# LazRandR

A display configuration tool for X11 that also maps touchscreens to the right
monitor — the part every desktop environment's display panel leaves out.

Built with Lazarus/FPC, GTK3, BGRABitmap.

---

## Why

Cinnamon's display settings (and GNOME's, and most others) can move monitors
around and rotate them. What none of them do is tell an **absolute input
device** — a touchscreen, a pen — which monitor it belongs to.

X reports touch coordinates across the *entire* virtual desktop. So on a
multi-monitor setup, touching the left edge of a portable panel sitting at
x=3840 puts the cursor on whatever happens to occupy the left edge of the
whole desktop. Rotate the panel and it gets worse: the axes are now swapped
relative to the framebuffer too.

The fix is a per-device **Coordinate Transformation Matrix** that confines the
device to its output's rectangle and composes in the rotation. LazRandR
computes that matrix, applies it, and — crucially — writes it into a replay
script so it survives a logout.

The second thing missing: Cinnamon only persists a layout applied through its
own panel. Anything set with `xrandr` leaves no `~/.config/monitors.xml`
behind, so it is gone on next login. LazRandR persists both halves itself.

## What it does

- **Drag-and-drop layout** — custom-drawn canvas with edge, centre and
  flush-alignment snapping (hold `Alt` to place freely), live snap guides.
- **Per-output settings** — resolution, refresh rate, orientation, primary,
  enable/disable.
- **Touch mapping** — enumerates touch/stylus devices, shows which output each
  is currently bound to, and confines any device to any output. Correct under
  rotation.
- **Persistence** — saves named profiles and generates a replay script that
  restores geometry *and* touch mapping; optional autostart entry runs it at
  login.
- **Reverse PRIME** — detects a non-NVIDIA sink provider and can emit the
  `--setprovideroutputsource` link needed when a panel hangs off a different
  GPU than the desktop renders on.
- **Identify** — numbered card on each screen, matching the canvas tiles.

## Building

Requires the fpcupdeluxe Lazarus/FPC trunk install at
`/media/tony/storpart/fpctrunklaztrunk`, with `BGRABitmapPack` and
`BGRAControls` registered.

```bash
./build.sh              # build
./build.sh --clean      # wipe lib/ and the binary first
./build.sh --verbose    # full compiler log
./run.sh                # build if needed, then run
```

The widgetset is pinned to **gtk3** — the only one compiled in that Lazarus
install, and what the forms are laid out against.

> `build.sh` touches a `.pas` whenever its `.lfm` is newer. lazbuild decides
> what to recompile from the `.pas` timestamp alone, so editing a form in the
> designer would otherwise relink the *old* form resource and the change would
> silently vanish.

## Editing the forms

All three forms (`ufrmmain`, `ufrmscriptpreview`, `ufrmidentify`) are real LFMs
and open in the Lazarus designer.

The one thing not on a form is `TLayoutCanvas`, created at runtime into the
`pnlCanvasHost` panel. It lives in this project rather than an installed
package, so the designer could not instantiate it — putting it on the LFM would
stop the form opening at all.

Styling is applied at runtime from `uTheme`, so the LFMs stay free of long
nested style blocks and remain easy to edit by hand.

## Layout of the code

| Unit | Role |
|---|---|
| `udisplaytypes.pas` | Shared records; the CTM maths (`BuildCTM`) |
| `uxrandr.pas` | Parse `xrandr`, build and run the apply command, providers |
| `utouch.pas` | Enumerate input devices, read/compute/apply matrices |
| `uprofiles.pas` | Profiles, replay script, autostart entry |
| `utheme.pas` | Palette, control skinning, shared BGRA drawing helpers |
| `ulayoutcanvas.pas` | The drag/snap canvas (runtime control) |
| `ufrmmain` / `ufrmscriptpreview` / `ufrmidentify` | Forms + LFMs |

Config and generated files live in `~/.config/lazrandr/`.

## Removed: virtual screen splitting

Earlier versions tried to split one monitor into several virtual ones with
`xrandr --setmonitor`. That code was complete — five split modes, a context
menu, correct command generation — but gated behind a check that disabled it
on Cinnamon, GNOME, MATE, Budgie and Unity, because those window managers
ignore XRandR monitors for snapping and maximise. It could never do anything
useful here, so it is gone rather than left as dead weight.
