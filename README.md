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
- **Login screen** — writes the same layout into the display manager's own
  setup hook, which is the only place the greeter can be reached. See below.
- **Reverse PRIME** — detects a non-NVIDIA sink provider and can emit the
  `--setprovideroutputsource` link needed when a panel hangs off a different
  GPU than the desktop renders on.
- **Identify** — numbered card on each screen, matching the canvas tiles.
- **Confirm or revert** — geometry changes are provisional. The previous
  layout *and* every input matrix are captured first, and a 15 second
  countdown puts them back unless you confirm, so a bad mode or a lost
  primary output cannot strand you with no way to undo it.
- **Inactive tray** — disabled outputs are parked in a permanent strip along
  the top rather than left at stale desktop coordinates where they hide
  underneath an active screen. Drag out to switch on, drop in to switch off.
- **Per-tile controls** — rotate, set primary and switch off directly on the
  selected screen.
- **Interface scale** — 100/200/300/400%, the same Cinnamon setting its own
  display panel drives. Global on X11, not per-monitor.

## Building

Requires the fpcupdeluxe Lazarus/FPC trunk install at
`/media/tony/storpart/fpctrunklaztrunk`, with `BGRABitmapPack` and
`BGRAControls` registered.

```bash
./build.sh              # optimised build (default)
./build.sh --debug      # range/overflow checks, debug info, heaptrc
./build.sh --clean      # wipe lib/ and the binary first
./build.sh --verbose    # full compiler log
./run.sh                # build if needed, then run
```

Release is `-O3`, smart-linked and stripped (~6 MB); Debug keeps the checks
and symbols and builds to a separate output directory.

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
| `ugreeter.pas` | Detect the login manager, generate and install its hook |
| `utheme.pas` | Palette, control skinning, shared BGRA drawing helpers |
| `ulayoutcanvas.pas` | The drag/snap canvas (runtime control) |
| `ufrmmain` / `ufrmscriptpreview` / `ufrmidentify` / `ufrmgreeter` | Forms + LFMs |

Config and generated files live in `~/.config/lazrandr/`.

## The login screen

A session autostart entry runs far too late to help the greeter, so a layout
that is correct on the desktop can still come up mirrored at the login screen.

The cause is a startup race, not a missing setting. The X server sizes its
screen from whichever outputs have completed their handshake at the moment the
video driver validates modes. An output that wakes a second or two later
cannot be placed at its saved position, because the screen was never made big
enough to hold it — so X puts it at `+0+0` and you get a mirror. On the
machine this was written for, the second 4K panel is consistently ~1.7 s late:

```
[ 9.548] NVIDIA(0): Virtual screen size determined to be 3840 x 2160   # one panel up
[11.136] NVIDIA(GPU-0): Samsung LS32A70 (DFP-0): connected             # second panel
[11.186] NVIDIA(0): Setting mode "HDMI-1 ... +0+0, HDMI-0 ... +0+0"    # mirrored
```

**Login Screen…** in the footer generates a setup script, shows it, and — via
a single `pkexec` call — installs it as the display manager's hook:

| Manager | Hook |
|---|---|
| LightDM | `display-setup-script` in `/etc/lightdm/lightdm.conf.d/60-lazrandr.conf` |
| SDDM | `DisplayCommand` in `/etc/sddm.conf.d/60-lazrandr.conf`, chaining the distribution's `Xsetup` |
| GDM | not supported — no drop-in directory, and GDM defaults to Wayland |

The script itself is written to be unable to lock you out:

- every path ends in `exit 0`, so a failure cannot stop the seat starting;
- the wait for late outputs is bounded by a deadline, not open-ended;
- outputs are applied **individually**, because one `--output` naming a
  connector that is not there makes `xrandr` reject the whole command line;
- if the layout is rejected anyway, it falls back to the primary output alone;
- it logs to `/var/log/lazrandr-greeter.log`.

Outputs are matched by connector name first, then by EDID physical size, and
only when exactly one unclaimed output carries that size. Connector names are
not stable — an output behind a DisplayPort hub or on a second GPU comes back
as `DP-1-1` one boot and `DP-2-1` the next — but two identical monitors cannot
be told apart by size, so the fallback refuses to guess rather than swapping
them.

Test it with a reboot, not a logout: a logout reuses the X server that is
already running, so it cannot show you whether the race is fixed.

## Known: a screen below the panel-bearing ones is unreachable

Not a LazRandR bug, but it bites the exact layout this tool exists for.

A Cinnamon panel publishes a strut, and a bottom-edge strut is defined as a
distance from the **screen** edge, not from its own monitor's edge. Put a
smaller screen *below* your main monitors and a 40 px taskbar at the bottom of
a 4K whose lower edge is at y=2160 turns into a 1080+40 px strut on a screen
3240 px tall:

```
$ xrandr | head -1
Screen 0: current 7680 x 3240
$ xprop -root _NET_WORKAREA
_NET_WORKAREA(CARDINAL) = 0, 0, 7680, 2120
```

The lower screen is entirely outside the work area, and muffin will not let a
titlebar be dragged out of it. The struts are *partial*, so the block only
covers the x-range each panel spans — which is why leaving a gap between the
upper monitors opens a corridor a window can be sneaked through.

Fixes, in order of how little they cost:

1. Move the panels to the **top** of the upper monitors. A top strut grows
   downward from y=0 and leaves the bottom of the screen alone.
2. Arrange the small screen **beside** the others rather than below, so
   nothing extends past their bottom edge.
3. `Super`+`Shift`+`Down` (`move-to-monitor-down`) ignores the drag
   constraint entirely and works as-is.

## Removed: virtual screen splitting

Earlier versions tried to split one monitor into several virtual ones with
`xrandr --setmonitor`. That code was complete — five split modes, a context
menu, correct command generation — but gated behind a check that disabled it
on Cinnamon, GNOME, MATE, Budgie and Unity, because those window managers
ignore XRandR monitors for snapping and maximise. It could never do anything
useful here, so it is gone rather than left as dead weight.
