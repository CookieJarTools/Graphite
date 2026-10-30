#!/usr/bin/env bash
# The person's desktop, started by the login screen (greeter.qml, through greetd, which has
# already read the system's profile): Hyprland, with its start-up messages kept off the text
# console, so nothing but the desktop shows. Its own log is in $XDG_RUNTIME_DIR/hypr as always.
# Before it, what makes apps open quickly and at all:
#   - folders apps from Flathub appear in, made now so the launcher watches them from the start;
#   - which helpers answer apps' requests (file pickers, settings): without this, GTK apps such
#     as Files can wait out a timeout before their window shows;
#   - with NVIDIA's driver: apps from Flathub get the part that matches it (they don't open
#     without it), and WebKit apps (the Modrinth App) skip a way of drawing that NVIDIA lacks;
#   - a keyring for apps' saved sign-ins (Unity Hub, VS Code), as Windows' Credential Manager:
#     without one they sign out whenever they close. It has no password of its own, so it opens
#     whether the person signed in with the PIN or the password, and never asks; the keyring
#     service starts when an app first needs it.
mkdir -p "$HOME/.local/share/flatpak/exports/share/applications" "$HOME/.local/share/applications"

keyrings="$HOME/.local/share/keyrings"
if command -v gnome-keyring-daemon >/dev/null && [ ! -e "$keyrings/default" ]; then
    mkdir -p -m 700 "$keyrings"
    [ -e "$keyrings/login.keyring" ] ||
        printf '[keyring]\ndisplay-name=Login\nctime=%s\nmtime=0\nlock-on-idle=false\nlock-after=false\n' "$(date +%s)" > "$keyrings/login.keyring"
    echo login > "$keyrings/default"
fi

portals="$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
if [ ! -f "$portals" ]; then
    mkdir -p "$(dirname "$portals")"
    printf '[preferred]\ndefault=hyprland;gtk\norg.freedesktop.impl.portal.Settings=gtk\norg.freedesktop.impl.portal.FileChooser=gtk\n' > "$portals"
fi

if [ -e /sys/module/nvidia ] && command -v flatpak >/dev/null; then
    (
        flatpak override --user --env=WEBKIT_DISABLE_DMABUF_RENDERER=1 com.modrinth.ModrinthApp 2>/dev/null
        want="GL.nvidia-$(tr . - < /sys/module/nvidia/version)"
        if flatpak list --app --columns=application 2>/dev/null | grep -q . &&
            ! flatpak list --runtime --columns=application 2>/dev/null | grep -q "$want"; then
            nice flatpak update --user -y --noninteractive >/dev/null 2>&1
        fi
    ) &
fi

exec start-hyprland > /dev/null 2>&1
