#!/usr/bin/env bash
# The person's desktop, started by the login screen (greeter.qml, through greetd, which has
# already read the system's profile): Hyprland, with its start-up messages kept off the text
# console, so nothing but the desktop shows. Its own log is in $XDG_RUNTIME_DIR/hypr as always.
# Folders apps from Flathub appear in, made now so the launcher watches them from the start
# (a folder that only appears with the first install is otherwise missed until the next sign-in).
mkdir -p "$HOME/.local/share/flatpak/exports/share/applications" "$HOME/.local/share/applications"
exec start-hyprland > /dev/null 2>&1
