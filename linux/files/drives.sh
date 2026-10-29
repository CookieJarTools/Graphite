#!/usr/bin/env bash
# The Drives place in Files, as Windows' This PC: a folder with a link to this computer's own
# drive and one to every drive connected, where Files' Size column (folder-sizes.py) shows the
# space left on each. It sits at the top of Files' sidebar. The shell runs this at start and
# whenever a drive connects or disconnects (services/Drives.qml).
place="${XDG_DATA_HOME:-$HOME/.local/share}/graphite/Drives"
mkdir -p "$place"

# Only links live there, all of them made here.
find "$place" -mindepth 1 -maxdepth 1 -type l -delete
ln -sfn / "$place/This computer"
for drive in /run/media/"$USER"/* /media/"$USER"/* /mnt/*; do
    mountpoint -q "$drive" 2>/dev/null && ln -sfn "$drive" "$place/$(basename "$drive")"
done

# In Files' sidebar, once.
bookmarks="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$bookmarks")"
grep -qF "file://$place " "$bookmarks" 2>/dev/null || printf 'file://%s Drives\n' "$place" >> "$bookmarks"
exit 0
