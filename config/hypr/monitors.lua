-- Append to ~/.config/hypr/monitors.lua
--
-- Lenovo Yoga Book 9 13IRU8 (82YQ): two stacked internal panels.
-- eDP-1 is the upper panel and is mounted 180 degrees out, so it needs
-- transform 2. eDP-2 sits directly below it (1440x900 logical at scale 2).
--
-- Do NOT also set video=eDP-1:panel_orientation=upside_down on the kernel
-- command line. It fixes the upside-down boot splash, but Hyprland's backend
-- reads the same property and rotates the scanout WITHOUT remapping input --
-- the image looks right while the pointer travels backwards. See the "boot
-- splash" entry under Open items in the README.
hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 2 })
hl.monitor({ output = "eDP-2", mode = "2880x1800@60", position = "0x900", scale = 2 })
