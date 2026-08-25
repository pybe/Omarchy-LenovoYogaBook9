# Omarchy on the Lenovo Yoga Book 9i

Notes and config for running [Omarchy](https://omarchy.org/) on a **Lenovo Yoga Book 9 13IRU8** (machine type `82YQ`) — the dual-screen laptop with two 13.3" 2880x1800 OLED panels.

Omarchy installs and runs fine on this machine, but the dual-screen hardware hits a few things that no amount of clicking around will fix, because they need config that doesn't exist by default. This documents each one: what you see, what's actually causing it, and the fix.

[`HARDWARE.md`](HARDWARE.md) has the full device inventory from a working install — displays, backlights, input devices, sensors, audio, power — with the command behind each table, so you can diff your unit against a known-good one.

## System this was worked out on

| | |
|---|---|
| Model | Lenovo Yoga Book 9 13IRU8 (`82YQ`) |
| BIOS | `KXCN41WW` (2024-12-19) |
| Omarchy | 4.0.1-1 |
| Hyprland | 0.56.2 |
| Kernel | 7.1.9-arch1-2 |
| Panels | 2x Samsung 2880x1800@60, `eDP-1` (upper) and `eDP-2` (lower) |
| Boot | limine + UKI, plymouth, LUKS2 root, SDDM with autologin |

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

> **Do not also set `video=eDP-1:panel_orientation=upside_down` on the kernel command line.** It is the obvious way to fix the upside-down boot splash, and it breaks the pointer. See [the boot splash open item](#the-boot-splash-and-passphrase-prompt-are-upside-down--unresolved) before trying it.

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

> **Verifying this is physical only.** There is no CLI check for device bindings on this build — see [Tooling notes](#tooling-notes). Test by touching each screen.

---

## Quirk 5 — no bass: the woofers are never fed

### What you see

Sound is thin and treble-heavy at any volume. Nothing is muted and volume behaves normally — there is simply no low end.

### Why

The codec presents two speaker pins, and the kernel classifies them as **front and surround** rather than tweeters and woofers:

```
Node 0x17  "Speaker Playback Switch"       <- tweeters, fed by DAC 0x03
Node 0x14  "Bass Speaker Playback Switch"  <- woofers,  fed by DAC 0x02
```

The driver also creates `Speaker Front Phantom Jack` **and** `Speaker Surround Phantom Jack`, which gives the game away. A stereo stream only ever reaches the front DAC, so `0x14` receives nothing and the woofers stay silent.

Confirm it in seconds — with music playing, mute only the main speakers:

```bash
amixer -c 0 cset numid=7 off    # Speaker (0x17) off
amixer -c 0 cset numid=9 on     # Bass Speaker (0x14) on
```

Total silence means the woofers are getting nothing. Turn `numid=7` back on afterwards.

Everything in the mixer looks correct, which is what makes this confusing: `Bass Speaker Playback Switch` is on, `DAC2 Playback Volume` is at maximum, the pin has `Pin-ctls: 0x40: OUT` and EAPD asserted. The problem is upstream of the mixer.

Related, and probably the same root cause — no model-specific codec quirk matched:

```
snd_hda_codec_alc269 ehdaudio0D0: ALC287: picked fixup  for PCI SSID 17aa:3843
```

Note the blank fixup name. The kernel does contain `ALC287_FIXUP_LENOVO_YOGA_BOOK_9I`, but it has no model string, so it cannot be forced with a module parameter — it only applies via the SSID quirk table.

### Fix

Rather than patch the kernel, open the sink with four channels so the surround pair carries audio, and upmix to generate it. Drop [this file](config/wireplumber/51-yoga-bass-speakers.conf) into `~/.config/wireplumber/wireplumber.conf.d/` and restart WirePlumber:

```
audio.channels = 4
audio.position = [ FL, FR, RL, RR ]
channelmix.upmix = true
channelmix.upmix-method = psd
```

```bash
systemctl --user restart wireplumber
wpctl inspect @DEFAULT_AUDIO_SINK@ | grep audio.channels    # expect 4
```

Bass returns immediately. Pure userspace, no kernel patch, survives kernel updates.

### Tone correction on top

Feeding the woofers fixes the missing bass, but these are small drivers in a thin chassis and still sound light. [`config/pipewire/60-bass-boost.conf`](config/pipewire/60-bass-boost.conf) adds a fixed low shelf and a small upper-mid trim using PipeWire's **built-in** biquad filters — no plugins, no application running, loaded at startup:

```bash
install -Dm644 config/pipewire/60-bass-boost.conf \
  ~/.config/pipewire/pipewire.conf.d/60-bass-boost.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
wpctl set-default $(pw-dump | jq -r '.[]|select(.info.props."node.name"?=="bass_boost_sink")|.id')
```

Edit the `Gain` values and restart PipeWire to taste. Keep it modest — large boosts on small drivers give distortion, not depth.

### If you want a graphical equaliser

**Use [`jamesdsp`](https://aur.archlinux.org/packages/jamesdsp) (AUR).** It is a port of the Android app: a slider bank, a bass control, named presets. It works the way an equaliser on a phone, TV or car stereo works, which is what most people actually want.

```bash
yay -S jamesdsp
```

Then make it the default output and it processes everything:

```bash
wpctl set-default $(pw-dump | jq -r '.[]|select(.info.props."node.description"?=="JamesDSP Sink")|.id')
```

Add it to autostart with `Exec=jamesdsp --tray` so the effect persists across logins.

**`easyeffects` is the more commonly recommended option, and it is the wrong recommendation for most people.** It is a capable tool aimed at users comfortable with filter modes, IIR/FIR and per-band Q. If that is not you it will feel unusable rather than merely unfamiliar. It also carries three pitfalls worth knowing before you spend an afternoon on it:

1. **On Arch it ships without its equaliser.** `lsp-plugins-lv2` is an *optional* dependency, so installing `easyeffects` alone gives an Equalizer that appears in the pipeline as `ee_soe_equalizer` with **no controls and no audible effect** — indistinguishable from a broken audio stack. Install `lsp-plugins-lv2 calf mda.lv2 zam-plugins-lv2` alongside it.
2. **It quits when you close its window**, taking the effect with it. Run it with `--hide-window` from autostart.
3. **It only processes audio routed into `easyeffects_sink`.** If that is not the default output, its controls do nothing. Check with `pw-link -l | grep ee_soe_`.

Whichever you choose, the equaliser is only tone shaping. The 4-channel fix above is the one that matters — without it the woofers receive no signal at all, and no amount of EQ will conjure bass out of a silent driver.

---

## Auto-brightness from the ambient light sensor

Not a quirk — a feature the hardware supports and nothing ships to use. Requires `iio-sensor-proxy`.

[`bin/yoga-autobrightness`](bin/yoga-autobrightness) reads the ALS over D-Bus and drives **both** backlights, with a [systemd user unit](config/systemd/yoga-autobrightness.service) to keep it running:

```bash
sudo pacman -S --needed iio-sensor-proxy && sudo systemctl enable --now iio-sensor-proxy
install -Dm755 bin/yoga-autobrightness ~/.local/bin/yoga-autobrightness
install -Dm644 config/systemd/yoga-autobrightness.service \
  ~/.config/systemd/user/yoga-autobrightness.service
systemctl --user daemon-reload && systemctl --user enable --now yoga-autobrightness
```

Three details that matter more than the sensor reading itself:

- **It sets both backlights directly** rather than calling `omarchy-brightness-display`, which resolves its target from the *focused monitor* — meaningless for a background daemon.
- **The curve is logarithmic.** Perceived brightness tracks the log of illuminance, so a linear map wastes most of its range on daylight levels nobody sits in. Roughly: 0 lux → 10%, 50 → 47%, 1000 → 76%, 10000 → 98%.
- **It stands down when you adjust brightness by hand.** If the panel is not where the daemon last left it, someone else moved it, so it pauses for ten minutes rather than fighting you. A threshold also stops it hunting over small fluctuations — the ALS drifts a few lux at rest.

The sensor only reports while claimed, so the daemon calls `ClaimLight` on start and `ReleaseLight` on exit:

```bash
busctl call net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy ClaimLight
busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy LightLevel
# d 73.025
```

---

## Applying all of it

```bash
git clone https://github.com/pybe/Omarchy-LenovoYogaBook9
cd Omarchy-LenovoYogaBook9

install -Dm755 bin/yoga-brightness ~/.local/bin/yoga-brightness

# Quirk 5 — bass speakers
install -Dm644 config/wireplumber/51-yoga-bass-speakers.conf \
  ~/.config/wireplumber/wireplumber.conf.d/51-yoga-bass-speakers.conf
systemctl --user restart wireplumber

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

Everything in Quirks 1-3 is verified on the system above, including across a full reboot: clean `hyprctl reload`, no config errors, layout and per-panel brightness both correct after restart, six brightness binds registered once each, and touch/stylus confirmed by hand on both panels.

The boot splash and passphrase prompt remain upside down. That is unresolved, not unattempted — see Open items for what was tried and why it was backed out.

## Tooling notes

Two things that cost real time on this machine and aren't obvious from any error message.

**`hyprctl keyword` does not work on Omarchy.** Omarchy configures Hyprland in Lua, so you get `keyword can't work with non-legacy parsers. Use eval.` Use `hyprctl eval` with the Lua helper instead:

```bash
hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 2 })'
```

**Device config cannot be verified from the CLI.** `hyprctl getoption device:<name>:<key>` returns `no such option` for *every* device key, including known-good ones on an ordinary mouse — it isn't reporting that your binding failed, it simply doesn't support device sections. `hyprctl devices -j` likewise exposes no output field for touch devices. A clean `hyprctl configerrors` tells you the config parsed and nothing more. Anything touch- or tablet-related has to be verified by hand.

## Open items

Found during a survey of the machine but not fixed. Listed with the evidence so nobody has to re-derive it. Contributions welcome.

### The boot splash and passphrase prompt are upside down — unresolved

Quirk 1 fixes orientation inside the compositor, which starts last. The kernel console, the plymouth splash and the LUKS passphrase prompt all take their cue from the DRM `panel orientation` property, which the kernel reports as `Normal` for this model:

```bash
modetest -c | grep -A3 'panel orientation'   # no privileges needed
#     enums: Normal=0 Upside Down=1 Left Side Up=2 Right Side Up=3
#     value: 0
```

**The obvious fix works for display and breaks the pointer.** Setting the true orientation on the kernel command line —

```
video=eDP-1:panel_orientation=upside_down
```

— does fix the boot splash and the passphrase prompt. But Hyprland's backend reads the same property (`libaquamarine.so` contains the string `panel orientation`; the `Hyprland` binary does not) and rotates the scanout, **without** applying that rotation to input mapping. The image comes out right and the pointer travels the wrong way on that panel.

The two settings are coupled, and there is no combination that satisfies both:

| Configuration | Boot splash | Desktop image | Pointer |
|---|---|---|---|
| Kernel param, no Hyprland transform | correct | correct | **inverted on eDP-1** |
| Kernel param **and** `transform = 2` | correct | **upside down** | correct-relative-to-image |
| No param, `transform = 2` *(what this repo ships)* | **upside down** | correct | correct |

There is no escape hatch. aquamarine exposes `AQ_DRM_DEVICES`, `AQ_FORCE_LINEAR_BLIT`, `AQ_LIBINPUT_NO_PLUGINS`, `AQ_MGPU_NO_EXPLICIT`, `AQ_NO_ATOMIC`, `AQ_NO_MODIFIERS` and `AQ_TRACEUH` — none disable orientation handling — and Hyprland has no config option for it either.

Tried on this machine and backed out. An unusable pointer on the main panel is worse than a cosmetic boot logo, especially since the passphrase prompt needs a USB keyboard regardless.

**The lower panel is not switched on yet when the prompt appears.** Observed boot sequence on this machine:

| Stage | Screen | Orientation |
|---|---|---|
| limine boot menu (firmware GOP) | upper only | **correct** |
| plymouth logo + passphrase prompt | upper only | upside down |
| plymouth progress bar, first ~2/3 | upper only | upside down |
| progress bar, last ~1/3 onward | both, mirrored | upper still upside down |
| desktop (Hyprland) | both | correct |

Two things follow. The firmware renders the upper panel correctly, so the inversion begins exactly when the kernel takes over the display — consistent with the missing DRM orientation quirk. And `eDP-2` only lights partway through plymouth's progress bar, well after the passphrase has been typed, so there is no lower panel to move the prompt onto at that moment. plymouth's DRM plugin logs `Found already lit monitor on connector %u` and `(Re)enumerating all outputs`, which fits: it attaches to whatever the firmware lit, then picks the second panel up later.

**Relocating the prompt to the lower panel is not configurable either.** plymouth's whole config surface is `Theme`, `ThemeDir`, `ShowDelay`, `DeviceScale` and `DeviceTimeout` — there is no output or connector selection. However, its DRM renderer groups connectors into "heads" and clones those whose modes match:

```
Adding connector with id %d to %dx%d head
connector %u uses same controller as %u and modes differ, unlinking controller
```

Both panels here are identical (2880x1800@60), so the prompt is likely already mirrored onto `eDP-2` the right way up, making "read the bottom screen" the practical workaround at zero config cost. Inferred from the plugin's strings, not yet confirmed by observation on this machine. Forcing the upper connector off at boot with `video=eDP-1:d` would probably also leave it dark in the desktop, so it is not a sensible trade.

For reference, if you want to experiment: Omarchy boots limine with a UKI, so the command line is assembled from `/etc/default/limine` plus `/etc/limine-entry-tool.d/*.conf`. Add a drop-in there and run `limine-mkinitcpio`; editing `/boot/limine.conf` directly is pointless because it is regenerated. Confirm what actually reached the UKI with:

```bash
sudo objcopy -O binary --only-section=.cmdline \
  /boot/EFI/Linux/omarchy_linux.efi /dev/stdout | tr -d '\0'
```

Note the property is only read at boot, so every iteration costs a reboot.

### A Bluetooth keyboard cannot answer the disk passphrase prompt

This machine ships with a **Bluetooth** keyboard and no built-in one, and on an encrypted install that is a genuine trap: the LUKS passphrase prompt runs in the initramfs, which has no Bluetooth stack at all. The `keyboard` hook covers USB HID only:

```
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap
       consolefont block encrypt filesystems fsck btrfs-overlayfs)
```

Note this comes from `/etc/mkinitcpio.conf.d/omarchy_hooks.conf`, not `/etc/mkinitcpio.conf` — the latter shows a stock hook list that is not what actually gets built.

No configuration fixes this. You need a USB keyboard to boot, or you need to remove the prompt. Do not be fooled into thinking it is a display-manager problem: SDDM autologin is already configured by Omarchy and fires without ever drawing a greeter, so the only password box on an encrypted install is the LUKS one.

```
sddm-helper: pam_unix(sddm-autologin:session): session opened for user <you>
```

**Solved on this machine — see [SECUREBOOT.md](SECUREBOOT.md).** Secure Boot was re-enabled with self-enrolled keys and the disk now unlocks from the TPM, so there is no passphrase prompt and no keyboard needed at boot. The prompt can be removed by enrolling the TPM, and the hardware supports it — TPM 2.0 at `/dev/tpm0`, LUKS2 with a single pbkdf2 keyslot and no TPM token. It requires switching the initramfs from the `encrypt` hook to `sd-encrypt`. **Weigh this carefully if Secure Boot is disabled**, as it is here: PCR-bound unlocking is materially weaker when unsigned code can boot and satisfy the same policy. Not done on this machine.

### Stylus palm rejection is paired to the wrong panel

libinput's touch-arbitration heuristic can't distinguish the two identical digitiser pairs presented by the single USB gadget, and ends up pairing **both** styluses to the bottom touchscreen:

```
event7  - touch-arbitration: activated for ...Stylus Top<->...Touchscreen Top
event7  - touch-arbitration: removing pairing for ...Stylus Top<->...Touchscreen Top
event7  - touch-arbitration: activated for ...Stylus Top<->...Touchscreen Bottom
event13 - touch-arbitration: activated for ...Stylus Bottom<->...Touchscreen Bottom
```

So resting a hand on the upper panel while drawing on it won't be arbitrated. This is below Hyprland — it needs a libinput quirks file, not compositor config.

### The emulated touchpad advertises a right button it shouldn't

```
[libinput] event14 - INGENIC Gadget Serial and keyboard Emulated Touchpad:
    kernel bug: clickpad advertising right button
```

The firmware's virtual touchpad on the lower panel declares itself a clickpad *and* advertises a physical right button, which libinput calls out as a [kernel bug](https://wayland.freedesktop.org/libinput/doc/1.31.3/clickpad-with-right-button.html). Expect right-click on the virtual touchpad to behave oddly. Fixing it properly means a libinput quirks file or a kernel-side fix; `clickfinger_behavior` in `input.lua` may be a usable workaround.

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

### Sensors work; auto-rotation still unwired

`iio-sensor-proxy` is not installed by default. Once installed, everything reports correctly:

```
=== Has accelerometer (orientation: normal, tilt: vertical)
=== Has ambient light sensor (value: 95.109005, unit: lux)
```

| Sensor | Notes |
|---|---|
| `als` | Working — drives auto-brightness, see below |
| `accel_3d` | Present, reports orientation |
| `gyro_3d` (x2) | Present |
| `hinge` | Exposes **three** angles: `in_angl0_raw` (hinge), `in_angl1_raw` (screen), `in_angl2_raw` (keyboard) |

**Auto-brightness is done** — see below. **Auto-rotation is not**, and needs care: the accelerometer reports orientation `normal` while `eDP-1` carries `transform = 2` because the panel is mounted 180° out. Rotation logic that ignores that offset will land 180° wrong. The three-angle hinge sensor is the obvious signal for switching display modes on a machine that folds.

### Battery charge limiting — available, but not where you would look

ACPI cannot resolve the embedded-controller charge object, and there are **no** `charge_control_*` attributes under `/sys/class/power_supply/BAT*/`:

```
ACPI Error: AE_NOT_FOUND, While resolving a named reference package element - \_SB_.PC00.LPCB.H_EC.CHRG
ACPI Error: AE_NOT_FOUND, While resolving a named reference package element - \_SB_.PC00.LPCB.H_EC.SEN3
```

That makes it look unsupported. It is not — `ideapad_laptop` exposes Lenovo's conservation mode on the platform device instead:

```bash
$ ls /sys/bus/platform/devices/VPC2004:00/
camera_power  conservation_mode  fan_mode  platform-profile  usb_charging  ...

$ cat /sys/bus/platform/devices/VPC2004:00/conservation_mode
0
```

Writing `1` caps charging (Lenovo's implementation stops around 55-60%) to preserve battery health. It is a toggle, not an arbitrary threshold.

`usb_charging`, `fan_mode` and `camera_power` are exposed on the same device.

Still genuinely missing: the `SEN3` thermal sensor is unreadable.

### Not investigated

- The virtual keyboard / trackpad overlay on the lower panel. Note the firmware presents its own `...-emulated-touchpad` device, so this is likely handled below the OS.
- Sleep/resume behaviour of the second panel's backlight.

## Confirmed working — don't go looking for problems here

- **Camera** is a plain UVC device (`04f2:b7c5`), not IPU6, so it works with no setup.
- **Power profiles** work via ACPI `platform_profile` (`low-power balanced performance`) with `power-profiles-daemon` active. The scary-looking `lenovo_wmi_gamezone ... platform_profile probe failed` in dmesg has no practical effect.
- **Bluetooth**, **PipeWire**, and the **battery** (100% of design capacity) are all healthy. No failed systemd units, system or user.

## Upstream

The input-mapping mismatch above looks like an aquamarine bug rather than a device quirk: applying a panel orientation to scanout while leaving the output's logical transform untouched makes display and input disagree by exactly that rotation. Any machine with a `panel_orientation` quirk or kernel parameter would hit it. Not filed upstream yet.

Quirk 2 is arguably an Omarchy bug rather than a device quirk — `omarchy-hw-display` returning a single device is a reasonable assumption that this hardware breaks. A general fix would make it return all internal backlights, or have `omarchy-brightness-display` resolve the backlight from the focused monitor rather than a global preference list. Not filed upstream yet.
