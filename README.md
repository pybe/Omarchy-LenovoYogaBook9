# Omarchy on the Lenovo Yoga Book 9i

Notes and config for running [Omarchy](https://omarchy.org/) on a **Lenovo Yoga Book 9 13IRU8** (machine type `82YQ`) — the dual-screen laptop with two 13.3" 2880x1800 OLED panels.

Omarchy installs and runs fine on this machine, but the dual-screen hardware hits a few things that no amount of clicking around will fix, because they need config that doesn't exist by default. This documents each one: what you see, what's actually causing it, and the fix.

## System this was worked out on

| | |
|---|---|
| Model | Lenovo Yoga Book 9 13IRU8 (`82YQ`) |
| BIOS | `KXCN41WW` (2024-12-19) |
| Omarchy | 4.0.1-1 |
| Hyprland | 0.56.2 |
| Kernel | 7.1.9-arch1-2 |
| Panels | 2x Samsung 2880x1800@60, `eDP-1` (upper) and `eDP-2` (lower) |

Panel identification matters throughout, and it is not guessable — **`eDP-1` is the upper screen and `eDP-2` is the lower one.** Confirm it on your own unit before applying anything, by changing one backlight and watching which screen reacts:

```bash
brightnessctl -d card1-eDP-2-backlight set 80%
```

---

## Quirk 1 — the top screen is upside down

### What you see

The upper panel renders inverted. Hyprland reports it as the primary display with workspace 1 on it, so this is also the screen you're mostly looking at. Both panels also sit side-by-side rather than stacked, so the mouse crosses left/right between two screens that are physically above and below each other.

### Why

The `eDP-1` panel is physically mounted 180° out relative to its scan direction. On hardware where this is known, the kernel ships a DRM panel-orientation quirk and corrects it before userspace ever sees it. There is no such quirk for the 13IRU8, so the panel comes up at `transform 0` and renders inverted:

```
$ hyprctl monitors -j | jq -r '.[] | "\(.name) @ \(.x),\(.y) transform=\(.transform)"'
eDP-1 @ 0,0 transform=0
eDP-2 @ 1440,0 transform=0
```

The side-by-side placement is just Omarchy's default `position = "auto"` doing the ordinary thing — it lays displays out horizontally because nothing tells it these two are stacked.

### Fix

Pin both panels explicitly in `~/.config/hypr/monitors.lua` ([snippet](config/hypr/monitors.lua)):

```lua
hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 2 })
hl.monitor({ output = "eDP-2", mode = "2880x1800@60", position = "0x900", scale = 2 })
```

`transform = 2` is the 180° flip. The `0x900` vertical offset stacks `eDP-2` directly beneath `eDP-1`: at `scale = 2` each 2880x1800 panel is 1440x900 logical pixels, so the lower panel starts at y=900. The cursor then moves up and down between screens the way the hardware is actually arranged.

Omarchy's stock `hl.monitor({ output = "", ... })` catch-all line stays where it is — these come after it and take precedence.

> **Note:** `hyprctl keyword monitor ...` does **not** work on Omarchy. Omarchy configures Hyprland in Lua, and you get `keyword can't work with non-legacy parsers. Use eval.` To test a monitor change live before committing it to config:
> ```bash
> hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 2 })'
> ```

---

## Quirk 2 — the bottom screen is stuck at minimum brightness

### What you see

The lower panel is dim and the brightness keys do nothing to it. They work normally — OSD and all — but only ever affect the upper screen. There is no key combination that fixes this, which is the tell that it isn't a settings problem.

### Why

This is a real structural limitation in Omarchy, not a misconfiguration.

The two panels have **separate backlight devices**:

```
$ ls /sys/class/backlight/
card1-eDP-2-backlight    intel_backlight
```

`intel_backlight` drives `eDP-1`; `card1-eDP-2-backlight` drives `eDP-2`. The brightness keys are bound to `omarchy-brightness-display`, which gets its target device from `omarchy-hw-display`. That script walks a fixed preference list and returns the **first** match:

```bash
for candidate in "$backlight_path"/gmux_backlight "$backlight_path"/amdgpu_bl* \
                 "$backlight_path"/intel_backlight "$backlight_path"/acpi_video*; do
  if [[ -e $candidate ]]; then
    device="${candidate##*/}"
    break
  fi
done
```

On this laptop that is always `intel_backlight`. The list has no concept of a machine with two internal panels, so `card1-eDP-2-backlight` is unreachable by the brightness keys by construction — it just sits wherever it was last left, which in a fresh install is near zero (4 out of 400 here, i.e. 1%).

### Fix

A wrapper that runs the stock command for `eDP-1` and then mirrors the resulting level onto `eDP-2`. Install [`bin/yoga-brightness`](bin/yoga-brightness) to `~/.local/bin/yoga-brightness` and make it executable.

Delegating to `omarchy-brightness-display` rather than reimplementing it keeps the OSD, the non-uniform step sizing near the bottom of the range, and the concurrent-keypress `flock`. The wrapper adds two guards: it does nothing on a bare query with no brightness argument, and it skips the mirror when the focused monitor is external, so driving a desk monitor over DDC doesn't drag the internal panel along with it.

Then rebind the keys in `~/.config/hypr/bindings.lua` ([snippet](config/hypr/bindings.lua)). **All six must be `hl.unbind`'d first** — they ship bound to `omarchy-brightness-display`, and without the unbind Hyprland fires both handlers. Keep `locked = true` so brightness still works on the lock screen, and `repeating = true` so held keys still repeat.

Finally, add the login sync in `~/.config/hypr/autostart.lua` ([snippet](config/hypr/autostart.lua)). `systemd-backlight` saves and restores the two panels independently across reboots, so `eDP-2` can come back dimmer than `eDP-1`; this re-syncs them at login. `+0%` is a no-op on `eDP-1` that exists purely to trigger the mirror.

### Consequence worth knowing

The brightness keys now move both panels **together**. To set them independently:

```bash
brightnessctl -d card1-eDP-2-backlight set 40%   # lower panel only
brightnessctl -d intel_backlight set 40%         # upper panel only
```

---

## Applying all of it

```bash
git clone https://github.com/pybe/Omarchy-LenovoYogaBook9
cd Omarchy-LenovoYogaBook9

install -Dm755 bin/yoga-brightness ~/.local/bin/yoga-brightness

# Back up first — these append to existing files.
for f in monitors bindings autostart; do
  cp ~/.config/hypr/$f.lua ~/.config/hypr/$f.lua.bak.$(date +%s)
  cat config/hypr/$f.lua >> ~/.config/hypr/$f.lua
done

hyprctl reload
hyprctl configerrors   # must print nothing
```

Verify:

```bash
# eDP-1 transform=2 at 0,0 and eDP-2 at 0,900
hyprctl monitors -j | jq -r '.[] | "\(.name) @ \(.x),\(.y) transform=\(.transform)"'

# exactly six binds, no duplicates
hyprctl binds -j | jq -r '.[] | select(.key | test("MonBrightness")) | "\(.modmask) \(.key) \(.description)"'

# both panels report the same level
yoga-brightness --no-osd 100%
for d in intel_backlight card1-eDP-2-backlight; do
  echo "$d: $(brightnessctl -d $d -m | awk -F, '{print $4}')"
done
```

## Status

Verified on the system above: clean `hyprctl reload`, no config errors, layout survives reload, six binds registered once each, both backlights tracking together.

**Not yet verified:** persistence across a full reboot. The `autostart.lua` sync is there to handle `systemd-backlight` restoring the panels at different levels, but it hasn't been observed across an actual reboot cycle yet.

## Open items

Not investigated, listed so nobody assumes they're solved. Contributions welcome.

- **Auto-rotation / hinge angle.** The hardware exposes the sensors — `als`, `accel_3d`, `gyro_3d` (x2) and a `hinge` sensor under `/sys/bus/iio/devices/` — but `iio-sensor-proxy` is `inactive`. Nothing currently reacts to folding the machine or changing its orientation, and the `hinge` sensor in particular looks like the intended signal for switching display modes.
- **Touchscreen and stylus**, including whether touch input maps to the correct panel once `transform = 2` is applied.
- **The virtual keyboard / trackpad overlay** on the lower panel, which on Windows is the main way the second screen gets used.
- **Speakers and the rotating soundbar.**
- **Sleep/resume** behaviour of the second panel's backlight.

## Upstream

Quirk 2 is arguably an Omarchy bug rather than a device quirk — `omarchy-hw-display` returning a single device is a reasonable assumption that this hardware breaks. A general fix would make it return all internal backlights, or have `omarchy-brightness-display` resolve the backlight from the focused monitor rather than a global preference list. Not filed upstream yet.
