#!/usr/bin/env bash
# Gives apps the desktop's look: GTK 4 (libadwaita: Files and most apps) and GTK 3 take its
# colours (graphite-dark.css or graphite-light.css, from gen-gtk-theme.js, with the accent
# chosen in the shell over them), the dark or light scheme, Inter, and the cursor theme, also
# set in Hyprland; kitty takes Vesper (linux/kitty/vesper.conf) with the same accent. The
# shell runs this at start and whenever its theme or accent changes (services/Desktop.qml):
#
#   apply.sh dark|light [accent-fill accent-text on-accent selection]
#
# The accent's fill (filled buttons), its text colour (links, focus), the words on the fill,
# and the terminal's selection colour; without them, Vesper's indigo.
scheme="${1:-dark}"
fill="${2:-#5b63e6}"
text="${3:-#9aa2ff}"
on_fill="${4:-#ffffff}"
selection="${5:-#262a52}"
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cursor="capitaine-cursors-light"
cursor_size=24

# The colours, then the accent over them. GTK 4 reads libadwaita's variables as well as the
# named colours; GTK 3 only the names. These were links to the colour files before the
# accent could change; a link is replaced by a file of its own.
accent_names="@define-color accent_color $text;
@define-color accent_bg_color $fill;
@define-color accent_fg_color $on_fill;
@define-color theme_selected_bg_color $fill;
@define-color theme_selected_fg_color $on_fill;"
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
rm -f "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
cat > "$HOME/.config/gtk-3.0/gtk.css" <<EOF
/* Written by Graphite (linux/gtk/apply.sh) whenever the theme or the accent changes. */
@import url("file://$here/graphite-$scheme.css");

$accent_names
EOF
cat > "$HOME/.config/gtk-4.0/gtk.css" <<EOF
/* Written by Graphite (linux/gtk/apply.sh) whenever the theme or the accent changes. */
@import url("file://$here/graphite-$scheme-gtk4.css");

$accent_names

:root {
  --accent-color: $text;
  --accent-bg-color: $fill;
  --accent-fg-color: $on_fill;
}
EOF

# The terminal: Vesper whatever the scheme, with the accent. kitty.conf is made only when
# there is none, to include graphite.conf first (so anything added below it wins); a kitty.conf
# of one's own is left as it is.
mkdir -p "$HOME/.config/kitty"
cat > "$HOME/.config/kitty/graphite.conf" <<EOF
# Written by Graphite (linux/gtk/apply.sh) whenever the accent changes.
include $here/../kitty/vesper.conf

color4               $text
url_color            $text
selection_background $selection
active_border_color  $fill
EOF
if [ ! -e "$HOME/.config/kitty/kitty.conf" ]; then
    cat > "$HOME/.config/kitty/kitty.conf" <<'EOF'
# kitty's settings. Graphite's look comes first (graphite.conf, which Graphite rewrites when
# its accent changes); anything below this line wins over it.
include graphite.conf
EOF
fi
# Open terminals take it at once.
pkill -USR1 -x kitty 2>/dev/null || true

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
