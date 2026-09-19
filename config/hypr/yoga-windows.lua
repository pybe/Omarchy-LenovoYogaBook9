-- Windows launched from the lower-screen keyboard open under it: touching the
-- panel focuses eDP-2, so the new window lands on that monitor's workspace.
-- While the panel is up, send every new window on eDP-2 to the upper screen.
-- With the panel hidden the lower screen behaves normally.

local function panel_open()
  return #hl.get_layers({ namespace = "yoga-input-panel" }) > 0
end

hl.on("window.open", function(window)
  local monitor = window.monitor
  if not monitor or monitor.name ~= "eDP-2" or not panel_open() then return end

  local target = hl.get_active_workspace("eDP-1")
  if not target then return end

  hl.dispatch(hl.dsp.window.move({
    workspace = tostring(target.id),
    window = "address:" .. window.address,
  }))
  hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
end)

-- The layout is tiling-only by default, so the pad pointer had no way to resize
-- a window. Grab the gap between windows with the pad's tap-and-drag instead;
-- the wider grab area makes a border hittable without pixel-precise aim.
hl.config({ general = { resize_on_border = true, extend_border_grab_area = 20 } })
