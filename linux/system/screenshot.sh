#!/usr/bin/env bash
# Screenshots: Print takes the whole screen, Super+Shift+S an area you drag out. The picture
# goes in Pictures/Screenshots and is copied too, ready to paste.
#   screenshot.sh [screen|area]
# xdg-user-dir answers the home folder itself when no Pictures folder is set up.
pictures="$(xdg-user-dir PICTURES 2>/dev/null)"
[ -n "$pictures" ] && [ "$pictures" != "$HOME" ] || pictures="$HOME/Pictures"
dir="$pictures/Screenshots"
mkdir -p "$dir"
file="$dir/Screenshot $(date '+%Y-%m-%d %H.%M.%S').png"
if [ "${1:-screen}" = area ]; then
    area="$(slurp -d)" || exit 0 # Escape: no screenshot
    grim -g "$area" "$file" || exit 1
else
    grim "$file" || exit 1
fi
wl-copy --type image/png < "$file"
notify-send -a "Graphite Desk" -i "$file" "Screenshot saved" "Saved to Pictures > Screenshots and copied, so you can paste it."
