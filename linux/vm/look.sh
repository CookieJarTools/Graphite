#!/usr/bin/env bash
# Runs a command in the desktop (optional), then lists the windows and saves a screenshot of
# the screen as shot.png next to this script (for checks from Windows).
here="$(dirname "$0")"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)"
export WAYLAND_DISPLAY=wayland-1
if [ $# -gt 0 ]; then hyprctl dispatch "hl.dsp.exec_cmd(\"$*\")"; sleep 6; fi
echo "== windows:"; hyprctl clients | grep -E 'class:|title:'
grim "$here/shot.png" && echo "== saved shot.png"
