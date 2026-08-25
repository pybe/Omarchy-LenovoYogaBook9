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

The `top` / `bottom` in the digitiser device names line up with this: `...-touchscreen-top` belongs to `eDP-1`, `...-touchscreen-bottom` to `eDP-2`. Verified by hand on this unit, but worth re-checking on yours.

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

## Quirk 3 — touch and stylus land on the wrong screen

### What you see

Touching a screen does something on the *other* screen. After applying the Quirk 1 rotation, touch on the upper panel is additionally 180° out — drag a window and it moves the opposite way.

### Why

The firmware exposes a separate digitiser per panel, four devices in total:

```
$ hyprctl devices
Tablets:  ...-stylus-top          ...-stylus-bottom
Touch:    ...-touchscreen-top     ...-touchscreen-bottom
```

Hyprland does not bind these to outputs on its own, and it has no way to infer which panel each belongs to. An unbound touch device doesn't map to a single screen, and — importantly — **an unbound device does not inherit any output transform**. That is why the upper panel's touch input is inverted once `transform = 2` is applied: the pixels are rotated but the touch coordinates aren't.

### Fix

Bind each digitiser to its panel in `~/.config/hypr/input.lua` ([snippet](config/hypr/input.lua)):

```lua
hl.device({ name = "ingenic-gadget-serial-and-keyboard-touchscreen-top", output = "eDP-1" })
hl.device({ name = "ingenic-gadget-serial-and-keyboard-stylus-top", output = "eDP-1" })
hl.device({ name = "ingenic-gadget-serial-and-keyboard-touchscreen-bottom", output = "eDP-2" })
hl.device({ name = "ingenic-gadget-serial-and-keyboard-stylus-bottom", output = "eDP-2" })
```

Binding to an output fixes both problems at once: input goes to the right screen, and the device picks up that output's transform.

> **Verifying this is physical only.** There is no CLI check. `hyprctl devices -j` reports no output field for touch devices, and `hyprctl getoption device:<name>:<key>` returns `no such option` for *every* device key — including known-good ones on an ordinary mouse — so it can't confirm or deny a binding. A clean `hyprctl configerrors` tells you the config parsed, nothing more. Test by touching each screen.

---

## Applying all of it

```bash
git clone https://github.com/pybe/Omarchy-LenovoYogaBook9
cd Omarchy-LenovoYogaBook9

install -Dm755 bin/yoga-brightness ~/.local/bin/yoga-brightness

# Back up first — these append to existing files.
for f in monitors bindings autostart input; do
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

Then the one check that has no CLI equivalent: **touch each screen and drag a window with your finger.** Input should act on the screen you're touching, and follow your finger rather than moving opposite to it.

## Status

Verified on the system above: clean `hyprctl reload`, no config errors, layout survives reload, six brightness binds registered once each, both backlights tracking together, and touch/stylus confirmed by hand to land on the correct screen the right way up on both panels.

**Not yet verified:** persistence across a full reboot. The `autostart.lua` sync is there to handle `systemd-backlight` restoring the panels at different levels, but it hasn't been observed across an actual reboot cycle yet.

## Open items

Found during a survey of the machine but not fixed. Listed with the evidence so nobody has to re-derive it. Contributions welcome.

### Stylus palm rejection is paired to the wrong panel

libinput's touch-arbitration heuristic can't distinguish the two identical digitiser pairs presented by the single USB gadget, and ends up pairing **both** styluses to the bottom touchscreen:

```
event7  - touch-arbitration: activated for ...Stylus Top<->...Touchscreen Top
event7  - touch-arbitration: removing pairing for ...Stylus Top<->...Touchscreen Top
event7  - touch-arbitration: activated for ...Stylus Top<->...Touchscreen Bottom
event13 - touch-arbitration: activated for ...Stylus Bottom<->...Touchscreen Bottom
```

So resting a hand on the upper panel while drawing on it won't be arbitrated. This is below Hyprland — it needs a libinput quirks file, not compositor config.

### Speaker amp calibration fails

```
tas2781-hda i2c-TIAS2781:00: tas2781_apply_calib: V1 CRC error
```

The TAS2781 smart amp rejects its calibration blob at every boot. Audio works, but an uncalibrated smart amp runs conservative, so expect thin and quiet output. The loaded topology is also the generic fallback rather than anything machine-specific:

```
loading topology: intel/sof-tplg/sof-hda-generic-2ch.tplg
snd_hda_codec_alc269 ehdaudio0D0: autoconfig for ALC287: line_outs=2 type:speaker
snd_hda_codec_alc269 ehdaudio0D0:    speaker_outs=0
```

### No sensor daemon, despite good sensor hardware

`iio-sensor-proxy` is not installed, so nothing reacts to orientation, folding, or ambient light. The hardware is all present and live under `/sys/bus/iio/devices/`:

| Sensor | Notes |
|---|---|
| `als` | Working — returns real readings from `in_illuminance_raw` |
| `accel_3d` | Present |
| `gyro_3d` (x2) | Present |
| `hinge` | Exposes **three** angles: `in_angl0_raw` (hinge), `in_angl1_raw` (screen), `in_angl2_raw` (keyboard) |

That three-angle hinge sensor is the obvious signal for auto-switching display modes on a machine like this. Read 0 across all three while stationary during the survey; whether that needs the daemon driving it or just movement wasn't established.

### No firmware update path

`fwupd` isn't installed. BIOS is `KXCN41WW`, dated 2024-12-19. Given how much of this machine's behaviour is firmware-driven, worth having.

### No battery charge threshold

ACPI can't resolve the embedded-controller charge object, and no `charge_control_*` attributes appear under `/sys/class/power_supply/BAT*/`:

```
ACPI Error: AE_NOT_FOUND, While resolving a named reference package element - \_SB_.PC00.LPCB.H_EC.CHRG
ACPI Error: AE_NOT_FOUND, While resolving a named reference package element - \_SB_.PC00.LPCB.H_EC.SEN3
```

So charge limiting isn't available, and one thermal sensor (`SEN3`) is unreadable.

### Not investigated

- The virtual keyboard / trackpad overlay on the lower panel. Note the firmware presents its own `...-emulated-touchpad` device, so this is likely handled below the OS.
- Sleep/resume behaviour of the second panel's backlight.

## Confirmed working — don't go looking for problems here

- **Camera** is a plain UVC device (`04f2:b7c5`), not IPU6, so it works with no setup.
- **Power profiles** work via ACPI `platform_profile` (`low-power balanced performance`) with `power-profiles-daemon` active. The scary-looking `lenovo_wmi_gamezone ... platform_profile probe failed` in dmesg has no practical effect.
- **Bluetooth**, **PipeWire**, and the **battery** (100% of design capacity) are all healthy. No failed systemd units, system or user.

## Upstream

Quirk 2 is arguably an Omarchy bug rather than a device quirk — `omarchy-hw-display` returning a single device is a reasonable assumption that this hardware breaks. A general fix would make it return all internal backlights, or have `omarchy-brightness-display` resolve the backlight from the focused monitor rather than a global preference list. Not filed upstream yet.
