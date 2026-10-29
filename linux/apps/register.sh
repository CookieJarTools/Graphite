#!/usr/bin/env bash
# Makes install-app.sh the opener for app downloads (.deb, AppImage, Flatpak, Arch packages),
# so the browser's "Open" or a double click in Files installs them; folders, pictures, PDFs and
# videos open in the desktop's own apps; Files gets folder sizes, a Drives place and Delete
# Permanently; and adds Flathub for the app store. The shell runs this at start; it is quick and safe to repeat.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
applications="$HOME/.local/share/applications"
mkdir -p "$applications"

types="application/vnd.debian.binary-package application/x-deb application/x-debian-package \
application/vnd.appimage application/x-appimage application/x-iso9660-appimage \
application/vnd.flatpak.ref application/vnd.flatpak application/x-alpm-package"

cat > "$applications/graphite-install.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Install app
Comment=Installs a downloaded app where it belongs
Icon=system-software-install
Exec=bash "$here/install-app.sh" %f
NoDisplay=true
MimeType=$(tr ' ' ';' <<<"$types" | tr -s ';');
ENTRY

command -v xdg-mime >/dev/null && xdg-mime default graphite-install.desktop $types

# Folders, pictures, documents and videos open in the desktop's own apps rather than in the
# terminal (Kitty's "kitty-open" claims folders, pictures and text); a choice of the person's own stays.
prefer() {
    local app="$1" type current
    shift
    [ -f "/usr/share/applications/$app" ] || [ -f "$applications/$app" ] || return 0
    for type in "$@"; do
        current="$(xdg-mime query default "$type" 2>/dev/null)"
        if [ -z "$current" ] || [ "$current" = kitty-open.desktop ]; then
            xdg-mime default "$app" "$type"
        fi
    done
}
if command -v xdg-mime >/dev/null; then
    prefer org.gnome.Nautilus.desktop inode/directory
    prefer org.gnome.Loupe.desktop image/png image/jpeg image/gif image/webp image/bmp image/svg+xml image/tiff image/avif image/heic
    prefer org.gnome.Papers.desktop application/pdf
    prefer io.github.celluloid_player.Celluloid.desktop video/mp4 video/x-matroska video/webm video/quicktime video/x-msvideo
fi
command -v update-desktop-database >/dev/null && update-desktop-database "$applications" 2>/dev/null

# Files: "Delete Permanently" in its menus, and a Size column that gives folders their size too
# (../files/folder-sizes.py, with Arch's nautilus-python), in place of its own Size column when
# its columns are still as they came.
extensions="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions"
mkdir -p "$extensions"
ln -sfn "$here/../files/folder-sizes.py" "$extensions/graphite-folder-sizes.py"
# And the Drives place in its sidebar, with the space left on each drive.
bash "$here/../files/drives.sh"
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.nautilus.preferences show-delete-permanently true
    if [ -f /usr/lib/nautilus/extensions-4/libnautilus-python.so ] &&
        [ "$(gsettings get org.gnome.nautilus.list-view default-visible-columns)" = "['name', 'size', 'date_modified']" ]; then
        gsettings set org.gnome.nautilus.list-view default-visible-columns "['name', 'graphite_size', 'date_modified']"
    fi
fi
if command -v flatpak >/dev/null; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    # Flathub's catalogue, for searching it in the Apps window (in the background: it downloads).
    (flatpak update --user --appstream flathub >/dev/null 2>&1 &)
fi
exit 0
