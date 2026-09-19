-- Title bars for a machine driven by touch: drag a window by its bar, close it
-- with the button. From the hyprbars plugin, which yoga-panel builds and loads
-- (yoga-panel/build-hyprbars.sh, ensure-plugin.py). The plugin registers
-- hl.plugin.hyprbars on load and reloads the config, so this block only runs
-- once the plugin exists -- until then it must not be a config error.

if not (hl.plugin and hl.plugin.hyprbars) then return end

hl.config({
  plugin = {
    hyprbars = {
      bar_height = 24,
      bar_text_size = 10,
      bar_padding = 8,
      bar_button_padding = 6,
      bar_color = "rgba(1e1e2ee6)",
      ["col.text"] = "rgb(cdd6f4)",
    },
  },
})

hl.plugin.hyprbars.add_button({
  bg_color = "rgb(e06c75)",
  fg_color = "rgb(1e1e2e)",
  size = 16,
  icon = "✕",
  action = "hyprctl eval 'hl.dispatch(hl.dsp.window.close())'",
})
