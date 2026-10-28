#!/usr/bin/env bash
# Runs a command inside the desktop's environment (Hyprland and the shell can be reached)
# and keeps its output in run.txt next to this script, for checks from Windows:
#   bash run.sh 'hyprctl clients -j'
here="$(dirname "$0")"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)"
export WAYLAND_DISPLAY=wayland-1
bash -c "$1" > "$here/run.txt" 2>&1
echo "exit $?" >> "$here/run.txt"
