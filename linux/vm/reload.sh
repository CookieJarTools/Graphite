#!/usr/bin/env bash
# Reloads Hyprland's config in the running desktop and reports errors and the screen's scale
# (for checks from Windows).
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)"
hyprctl reload
sleep 2
echo "== config errors:"; hyprctl configerrors
echo "== scale:"; hyprctl monitors | grep -E 'scale|^Monitor|@'
echo "== env:"; tr '\0' '\n' < "/proc/$(pgrep -x Hyprland)/environ" | grep LIBGL
