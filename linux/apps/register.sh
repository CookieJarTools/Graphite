#!/usr/bin/env bash
# Makes install-app.sh the opener for app downloads (.deb, AppImage, Flatpak, Arch packages),
# so the browser's "Open" or a double click in Files installs them; and adds Flathub for the
# app store. The shell runs this at start; it is quick and safe to repeat.
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
command -v update-desktop-database >/dev/null && update-desktop-database "$applications" 2>/dev/null
if command -v flatpak >/dev/null; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    # Flathub's catalogue, for searching it in the Apps window (in the background: it downloads).
    (flatpak update --user --appstream flathub >/dev/null 2>&1 &)
fi
exit 0
