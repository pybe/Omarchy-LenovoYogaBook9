# Hardware inventory and diagnostics

Reference data captured from a working Omarchy install on a Lenovo Yoga Book 9 13IRU8 (`82YQ`), for comparison against your own unit. Every command used to produce it is shown, so you can re-run the survey.

Captured 2026-08-25 on Omarchy 4.0.1-1, Hyprland 0.56.2, kernel 7.1.9-arch1-2.

## Displays

```bash
hyprctl monitors all
```

```
eDP-1  Samsung Display Corp. 0x4167
  mode 2880x1800@60  pos 0,0  scale 2  transform 2
eDP-2  Samsung Display Corp. 0x4182
  mode 2880x1800@60  pos 0,900  scale 2  transform 0
```

## Backlights

Two independent devices — this is the root of Quirk 2.

```bash
ls /sys/class/backlight/
brightnessctl -l
```

```
card1-eDP-2-backlight  max=400  type=raw  drives=eDP-2
intel_backlight  max=400  type=raw  drives=eDP-1
```

## Input devices

```bash
hyprctl devices
```

The four per-panel digitisers are the subject of Quirk 3:

```
touch    ingenic-gadget-serial-and-keyboard-touchscreen-top
touch    ingenic-gadget-serial-and-keyboard-touchscreen-bottom
tablet   ingenic-gadget-serial-and-keyboard-stylus-top
tablet   ingenic-gadget-serial-and-keyboard-stylus-bottom
```

Everything else libinput sees:

```
mouse    ingenic-gadget-serial-and-keyboard-keyboard-1
mouse    ingenic-gadget-serial-and-keyboard-emulated-touchpad
mouse    logitech-mx-anywhere-3
mouse    yb9-kb-keyboard-1
keyboard ingenic-gadget-serial-and-keyboard-keyboard
keyboard ideapad-extra-buttons
keyboard sof-hda-dsp-headset-jack
keyboard video-bus
keyboard intel-hid-events
keyboard intel-hid-5-button-array
keyboard power-button
keyboard sleep-button
keyboard at-translated-set-2-keyboard
keyboard yb9-kb-keyboard
keyboard hl-virtual-keyboard-fcitx5
switch   Lid Switch
```

## Sensors

```bash
for d in /sys/bus/iio/devices/iio:device*/; do echo "$(cat $d/name)"; done
```

```
als        iio:device0
accel_3d   iio:device1
gyro_3d    iio:device2
gyro_3d    iio:device3
hinge      iio:device4
```

The hinge device exposes three separate angles:

```
in_angl0_raw  = 0   (hinge)
in_angl1_raw  = 0   (screen)
in_angl2_raw  = 0   (keyboard)
```

## Audio

```bash
wpctl status
```

```
Sinks:
   59. Raptor Lake-P/U/H cAVS HDMI / DisplayPort 3 Output
   60. Raptor Lake-P/U/H cAVS HDMI / DisplayPort 2 Output
   61. Raptor Lake-P/U/H cAVS HDMI / DisplayPort 1 Output
 * 62. Raptor Lake-P/U/H cAVS Speaker
Sources:
 * 63. Raptor Lake-P/U/H cAVS Digital Microphone
```

One stereo Speaker sink, backed by an ALC287 codec plus a TAS2781 smart amp
whose calibration fails at boot — see Open items in the README.

```
api.alsa.card.longname = LENOVO-82YQ-YogaBook913IRU8-LNVNB161216
device.profile.name    = HiFi: Speaker: sink
audio.channels         = 2
topology               = intel/sof-tplg/sof-hda-generic-2ch.tplg
```

Camera is a plain UVC device (`04f2:b7c5`) exposing `/dev/video0..3`, and needs
no setup.

## Power

```
platform_profile choices : low-power balanced performance
platform_profile active  : balanced
power-profiles-daemon    : active
battery health           :  capacity: 100%
charge threshold support : none (see Open items)
```
