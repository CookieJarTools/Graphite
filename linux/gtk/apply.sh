#!/usr/bin/env bash
# Gives apps the Graphite look: GTK 4 (libadwaita: Files and most apps) and GTK 3 take the
# Graphite colours (graphite-dark.css or graphite-light.css, from gen-gtk-theme.js), the dark
# or light scheme, Inter, and the cursor theme, also set in Hyprland. The shell runs this at
# start and whenever its Dark mode setting changes:  apply.sh dark|light
scheme="${1:-dark}"
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cursor="capitaine-cursors-light"
cursor_size=24

for version in gtk-4.0 gtk-3.0; do
    mkdir -p "$HOME/.config/$version"
    ln -sfn "$here/graphite-$scheme.css" "$HOME/.config/$version/gtk.css"
done

# Text, the MacType way (fonts/fonts.conf; the stem darkening is in hyprland.lua).
mkdir -p "$HOME/.config/fontconfig"
ln -sfn "$here/../fonts/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"

if command -v gsettings >/dev/null; then
    interface=org.gnome.desktop.interface
    if [ "$scheme" = dark ]; then
        gsettings set $interface color-scheme prefer-dark
        gsettings set $interface gtk-theme Adwaita-dark
    else
        gsettings set $interface color-scheme default
        gsettings set $interface gtk-theme Adwaita
    fi
    gsettings set $interface font-name "Inter 10"
    gsettings set $interface monospace-font-name "JetBrains Mono 10"
    gsettings set $interface font-antialiasing rgba
    gsettings set $interface font-hinting slight
    gsettings set $interface font-rgba-order rgb
    gsettings set $interface cursor-theme "$cursor"
    gsettings set $interface cursor-size "$cursor_size"
fi

# The pointer Hyprland draws, resize shapes included.
if [ -d "/usr/share/icons/$cursor" ] && command -v hyprctl >/dev/null; then
    hyprctl setcursor "$cursor" "$cursor_size" >/dev/null
fi
