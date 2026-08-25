-- Append to ~/.config/hypr/autostart.lua
--
-- Match eDP-2's backlight to eDP-1 at login. systemd-backlight saves and
-- restores each panel independently, so eDP-2 can come back far dimmer.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/yoga-brightness --no-osd +0%")
