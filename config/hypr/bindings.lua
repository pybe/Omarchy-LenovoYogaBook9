-- Append to ~/.config/hypr/bindings.lua
--
-- Route the brightness keys through a wrapper that also drives the second
-- internal panel. Omarchy's default handler only ever touches eDP-1's
-- backlight. All six keys are unbound first: they ship bound to
-- omarchy-brightness-display, and Hyprland would otherwise fire both handlers.
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
