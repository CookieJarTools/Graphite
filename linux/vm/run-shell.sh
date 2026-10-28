#!/usr/bin/env bash
# Starts the shell inside the running desktop and keeps what it prints in shell.txt next to
# this script, then reports whether it is still up (for checks from Windows).
here="$(dirname "$0")"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)"
export WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland
pkill -x quickshell; pkill -x qs
# Arguments are extra environment for the shell, for example QT_QUICK_BACKEND=software.
setsid env "$@" qs -c graphite > "$here/shell.txt" 2>&1 < /dev/null &
sleep 8
echo "== running:"; pgrep -a -x quickshell; pgrep -a -x qs
echo "== layers:"; hyprctl layers
echo "== output:"; cat "$here/shell.txt"
