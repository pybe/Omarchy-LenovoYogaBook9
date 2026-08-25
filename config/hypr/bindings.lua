-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Yoga Book 9: route the brightness keys through a wrapper that also drives
-- the second internal panel. Omarchy's default handler only ever touches
-- eDP-1's backlight. Previously all six were bound to omarchy-brightness-display.
local yoga_brightness = os.getenv("HOME") .. "/.local/bin/yoga-brightness"
local yoga_brightness_keys = {
  { "XF86MonBrightnessUp", "Brightness up", "+5%" },
  { "XF86MonBrightnessDown", "Brightness down", "5%-" },
  { "SHIFT + XF86MonBrightnessUp", "Brightness maximum", "100%" },
  { "SHIFT + XF86MonBrightnessDown", "Brightness minimum", "1%" },
  { "ALT + XF86MonBrightnessUp", "Brightness up precise", "+1%" },
  { "ALT + XF86MonBrightnessDown", "Brightness down precise", "1%-" },
}

for _, entry in ipairs(yoga_brightness_keys) do
  local keys, description, step = entry[1], entry[2], entry[3]
  hl.unbind(keys)
  o.bind(keys, description, yoga_brightness .. " " .. step, { locked = true, repeating = true })
end

-- Yoga Book 9: route the volume keys through a wrapper that can resolve past a
-- DSP sink built on PipeWire links.
--
-- Omarchy deliberately reaches through DSP sinks to the physical one, but
-- omarchy-audio-output-sink does it by finding a PulseAudio sink-input whose
-- name matches the DSP sink, plus a hardcoded case for EasyEffects. JamesDSP
-- has no such sink-input -- it reaches the hardware over PipeWire links, two
-- hops via its own processing node -- so the resolver returns jamesdsp_sink and
-- the keys move a volume JamesDSP ignores: the OSD responds, the speakers do
-- not. Previously all five were bound to omarchy-audio-output-volume.
--
-- SHIFT + XF86AudioMute is the output switcher, not volume, and is left alone.
local yoga_volume = os.getenv("HOME") .. "/.local/bin/yoga-volume"
local yoga_volume_keys = {
  { "XF86AudioRaiseVolume", "Volume up", "raise", true },
  { "XF86AudioLowerVolume", "Volume down", "lower", true },
  { "XF86AudioMute", "Mute", "mute-toggle", false },
  { "ALT + XF86AudioRaiseVolume", "Volume up precise", "+1", true },
  { "ALT + XF86AudioLowerVolume", "Volume down precise", "-1", true },
}

for _, entry in ipairs(yoga_volume_keys) do
  local keys, description, action, repeating = entry[1], entry[2], entry[3], entry[4]
  hl.unbind(keys)
  o.bind(keys, description, yoga_volume .. " " .. action,
    { locked = true, repeating = repeating })
end
