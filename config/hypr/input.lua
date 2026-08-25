-- Append to ~/.config/hypr/input.lua
--
-- Bind each digitiser to the panel it physically sits on. The firmware
-- exposes a separate touchscreen and stylus per panel, and Hyprland leaves
-- them unbound by default, so input lands on the wrong screen. Binding also
-- makes each device inherit its output's transform, which is what keeps
-- touch aligned on eDP-1 (rotated 180 degrees).
local yoga_digitisers = {
  { "ingenic-gadget-serial-and-keyboard-touchscreen-top", "eDP-1" },
  { "ingenic-gadget-serial-and-keyboard-stylus-top", "eDP-1" },
  { "ingenic-gadget-serial-and-keyboard-touchscreen-bottom", "eDP-2" },
  { "ingenic-gadget-serial-and-keyboard-stylus-bottom", "eDP-2" },
}

for _, entry in ipairs(yoga_digitisers) do
  hl.device({ name = entry[1], output = entry[2] })
end
