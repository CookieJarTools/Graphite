#!/usr/bin/env bash
# Startup apps: everything in ~/.config/autostart (the Control Panel's Apps page adds and
# removes them) starts when the person signs in; hyprland.lua runs this once a session.
for entry in "$HOME/.config/autostart"/*.desktop; do
    [ -f "$entry" ] || continue
    grep -qi '^Hidden=true' "$entry" && continue
    gio launch "$entry" >/dev/null 2>&1 &
done
