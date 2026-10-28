#!/usr/bin/env bash
# Collects what the VM's desktop is doing into diag.txt next to this script (for checks from
# Windows through the shared folder).
out="$(dirname "$0")/diag.txt"
# From a text console, find the running Hyprland and the shell's display.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
{
    echo "== $(date)"
    echo "== id"; id
    echo "== mounts"; mount | grep -i -E 'vbox|StartMenu'
    echo "== links"; ls -la ~/.config/hypr ~/.config/quickshell
    echo "== processes"; pgrep -a -f 'Hyprland|quickshell|qs |kitty|VBox'
    echo "== monitors"; hyprctl monitors
    echo "== clients"; hyprctl clients
    echo "== layers"; hyprctl layers
    echo "== config errors"; hyprctl configerrors
    echo "== hyprland log"
    tail -80 "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
    echo "== shell log"; qs -c graphite log 2>&1 | tail -80
    echo "== gpu"; ls /dev/dri; journalctl -b -k --no-pager 2>/dev/null | grep -i -E 'vmwgfx|drm' | tail -20
} > "$out" 2>&1
