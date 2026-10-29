#!/usr/bin/env bash
# Installs a downloaded app where it belongs, so opening the file is all it takes (register.sh
# makes this the opener for these files; the browser's "Open" or a double click in Files runs
# it). Progress shows as a notification; the app then sits in the launcher like any other.
#
#   .deb (Ubuntu/Debian apps, e.g. Claude Desktop)  into an Ubuntu 24.04 container ("apps",
#                     made the first time, sharing home, display, sound and GPU), its menu
#                     entries exported to this desktop
#   .AppImage         kept in ~/Applications, made runnable, given a launcher entry
#   .flatpakref, .flatpak   installed with Flatpak (for this user)
#   .pkg.tar.zst      an Arch package, with pacman (asks for the password)
#
#   install-app.sh FILE              install
#   install-app.sh --flathub APP_ID  install an app from Flathub (the Apps window's Install)
#   install-app.sh --package NAME [--replaces APP_ID]
#                                    install one of Arch Linux's own packages (asks for the
#                                    PIN or password), and remove the Flathub copy it replaces
#   install-app.sh --remove ID       uninstall the app with desktop entry id ID: one this script
#                                    put there, a Flatpak app, or a system package (asks for
#                                    the password; the desktop's own parts are kept)
set -uo pipefail

box=apps
image=docker.io/library/ubuntu:24.04
manifests="$HOME/.local/share/graphite/apps"
applications="$HOME/.local/share/applications"
mkdir -p "$manifests" "$applications"

note=""
failing="Couldn't install"
notify() {
    local args=(-a "Graphite Desk" -i system-software-install -p)
    [ -n "$note" ] && args+=(-r "$note")
    note=$(notify-send "${args[@]}" "$1" "${2:-}" 2>/dev/null || true)
}

fail() {
    notify "$failing ${name:-the app}" "$1"
    exit 1
}

# The administrator's helper (system/graphite-admin): asks for the password or PIN once, then
# not again for a few minutes.
admin() { pkexec /usr/local/lib/graphite/graphite-admin "$@"; }

in_box() { distrobox enter --name "$box" -- "$@"; }

manifest() { # id kind key=value...
    local id="$1" kind="$2"; shift 2
    { printf 'kind=%s\n' "$kind"; printf '%s\n' "$@"; } > "$manifests/$id"
}

# ---------- removing ----------

if [ "${1:-}" = "--remove" ]; then
    failing="Couldn't uninstall"
    id="${2%.desktop}"
    name="$id"
    if [ -f "$manifests/$id" ]; then
        # shellcheck disable=SC1090
        source "$manifests/$id"
        notify "Uninstalling $id..."
        case "$kind" in
            deb)
                in_box distrobox-export --app "$desktop" --delete >/dev/null 2>&1
                in_box sudo apt-get remove -y "$package" >/dev/null 2>&1
                rm -f "$applications/$id.desktop"
                ;;
            appimage)
                rm -f "$path" "$applications/$id.desktop" "$icon"
                ;;
            pacman)
                admin package-remove "$package" || fail "It wasn't uninstalled. You may have cancelled, or other apps need it."
                ;;
        esac
        rm -f "$manifests/$id"
        notify "Uninstalled" "$id was removed."
        exit 0
    fi
    if flatpak info "$id" >/dev/null 2>&1; then
        notify "Uninstalling $id..."
        if flatpak info --user "$id" >/dev/null 2>&1; then
            flatpak uninstall --user -y --noninteractive "$id" >/dev/null 2>&1 || fail "Flatpak couldn't remove it."
        else
            admin flatpak-remove "$id" >/dev/null 2>&1 || fail "It wasn't uninstalled. You may have cancelled."
        fi
        notify "Uninstalled" "$id was removed."
        exit 0
    fi
    # A system package, unless it is part of the desktop itself.
    entry="/usr/share/applications/$id.desktop"
    if [ -f "$entry" ] && package="$(pacman -Qqo "$entry" 2>/dev/null)"; then
        case "$package" in
            hyprland | quickshell* | kitty | nautilus | gnome-software | hyprpolkitagent | xdg-desktop-portal* | networkmanager | bluez* | pipewire* | wireplumber)
                fail "$package is part of the desktop and can't be removed." ;;
        esac
        name="$(grep -m1 '^Name=' "$entry" | cut -d= -f2-)"
        notify "Uninstalling ${name:-$package}..." "Enter your PIN or password when asked."
        admin package-remove "$package" >/dev/null 2>&1 || fail "It wasn't uninstalled. You may have cancelled, or other apps need it."
        notify "Uninstalled" "${name:-$package} was removed."
        exit 0
    fi
    fail "This app can't be uninstalled from here."
fi

# ---------- from Flathub ----------

if [ "${1:-}" = "--flathub" ]; then
    app="${2:-}"
    name="$app"
    command -v flatpak >/dev/null || fail "Flatpak is missing; run linux/setup.sh."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    # Its own name (Zen Browser, not app.zen_browser.zen), from Flathub, for what's said.
    name="$(flatpak remote-info --user flathub "$app" 2>/dev/null | sed -n '2s/^\([^-]*\) - .*/\1/p' | sed 's/ *$//')"
    name="${name:-$app}"
    notify "Installing $name..." "From Flathub. Large apps can take a few minutes."
    flatpak install --user -y --noninteractive flathub "$app" >/dev/null 2>&1 || fail "Flathub couldn't install it. Check your internet connection."
    notify "$name is installed" "Press the Windows key and type its name to open it."
    exit 0
fi

# ---------- from Arch Linux's own packages ----------

if [ "${1:-}" = "--package" ]; then
    package="${2:-}"
    replaces="${4:-}"
    [ "${3:-}" = "--replaces" ] || replaces=""
    [[ "$package" =~ ^[a-z0-9@._+-]+$ ]] || fail "That isn't a package name."
    name="$package"
    notify "Installing $name..." "From Arch Linux. Enter your PIN or password if asked."
    admin package-install "$package" >/dev/null 2>&1 || fail "It wasn't installed. You may have cancelled, or you're offline."
    desktops="$(pacman -Qlq "$package" 2>/dev/null | grep -E '^/usr/share/applications/[^/]+\.desktop$')"
    for desktop in $desktops; do
        manifest "$(basename "$desktop" .desktop)" pacman "package=$package"
    done
    shown="$(grep -m1 '^Name=' $desktops /dev/null 2>/dev/null | head -1 | cut -d= -f2-)"
    name="${shown:-$name}"
    # Switching from the Flathub copy: that one goes once this one is in. Settings stay in the
    # home folder (~/.var/app), so nothing is lost if the person goes back.
    if [ -n "$replaces" ] && flatpak info "$replaces" >/dev/null 2>&1; then
        if flatpak info --user "$replaces" >/dev/null 2>&1; then
            flatpak uninstall --user -y --noninteractive "$replaces" >/dev/null 2>&1
        else
            admin flatpak-remove "$replaces" >/dev/null 2>&1
        fi
    fi
    notify "$name is installed" "Press the Windows key and type its name to open it."
    exit 0
fi

# ---------- installing ----------

file="$(readlink -f "${1:-}")"
[ -f "$file" ] || { notify "Nothing to install" "${1:-no file given}"; exit 1; }
base="$(basename "$file")"
name="$base"

# Inside the container only the home folder is the same; a file elsewhere comes in first.
inside_home() {
    case "$file" in
        "$HOME"/*) echo "$file" ;;
        *) mkdir -p "$HOME/.cache/graphite"; cp -f "$file" "$HOME/.cache/graphite/$base"; echo "$HOME/.cache/graphite/$base" ;;
    esac
}

install_deb() {
    command -v distrobox >/dev/null || fail "Distrobox is missing; run linux/setup.sh."
    if ! distrobox list --no-color 2>/dev/null | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -qx "$box"; then
        notify "Setting up Ubuntu apps" "This only happens once and takes a few minutes."
        distrobox create --yes --no-entry --name "$box" --image "$image" >/dev/null 2>&1 || fail "Couldn't set up Ubuntu apps. Check your internet connection."
    fi
    local deb package desktops
    deb="$(inside_home)"
    package="$(in_box dpkg-deb -f "$deb" Package 2>/dev/null | tr -d '\r')"
    [ -n "$package" ] || fail "$base isn't a valid .deb file."
    name="$package"
    notify "Installing $name..." "From $base"
    in_box sudo apt-get update -qq >/dev/null 2>&1
    in_box sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$deb" >/dev/null 2>&1 || fail "apt couldn't install $base."
    desktops="$(in_box dpkg -L "$package" 2>/dev/null | tr -d '\r' | grep -E '^/usr/share/applications/[^/]+\.desktop$' || true)"
    [ -n "$desktops" ] || fail "$name installed, but it has no app to open. It may be a command-line tool."
    local desktop shown=""
    for desktop in $desktops; do
        # Under its own name, not "Name (on apps)".
        in_box distrobox-export --app "$desktop" --export-label none >/dev/null 2>&1 || continue
        local id="$box-$(basename "$desktop" .desktop)"
        manifest "$id" deb "box=$box" "package=$package" "desktop=$desktop"
        shown="$(grep -m1 '^Name=' "$applications/$id.desktop" 2>/dev/null | cut -d= -f2-)"
    done
    notify "${shown:-$name} is installed" "Open it from the launcher."
}

install_appimage() {
    local folder="$HOME/Applications" target id work entry icon_file icon
    mkdir -p "$folder"
    target="$folder/$base"
    [ "$file" = "$target" ] || cp -f "$file" "$target"
    chmod +x "$target"
    id="appimage-$(basename "$base" .AppImage | tr -c 'A-Za-z0-9._-\n' '-' | tr 'A-Z' 'a-z')"
    notify "Installing $base..."
    work="$(mktemp -d)"
    ( cd "$work" && "$target" --appimage-extract '*.desktop' >/dev/null 2>&1 && "$target" --appimage-extract .DirIcon >/dev/null 2>&1 )
    entry="$(find "$work/squashfs-root" -maxdepth 1 -name '*.desktop' 2>/dev/null | head -1)"
    icon_file="$(readlink -f "$work/squashfs-root/.DirIcon" 2>/dev/null || true)"
    icon="$HOME/.local/share/icons/$id.png"
    mkdir -p "$(dirname "$icon")"
    if [ -f "$icon_file" ]; then cp -f "$icon_file" "$icon"; else icon="application-x-executable"; fi
    if [ -n "$entry" ]; then
        name="$(grep -m1 '^Name=' "$entry" | cut -d= -f2-)"
        sed -e "s|^Exec=[^ ]*|Exec=\"$target\"|" -e "s|^Icon=.*|Icon=$icon|" -e '/^TryExec=/d' "$entry" > "$applications/$id.desktop"
    else
        name="$(basename "$base" .AppImage)"
        printf '[Desktop Entry]\nType=Application\nName=%s\nExec="%s"\nIcon=%s\n' "$name" "$target" "$icon" > "$applications/$id.desktop"
    fi
    rm -rf "$work"
    manifest "$id" appimage "path=\"$target\"" "icon=\"$icon\""
    notify "$name is installed" "Open it from the launcher."
}

install_flatpak() {
    command -v flatpak >/dev/null || fail "Flatpak is missing; run linux/setup.sh."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1
    name="$(grep -m1 '^Title=' "$file" 2>/dev/null | cut -d= -f2-)"
    name="${name:-$base}"
    notify "Installing $name..." "With Flatpak"
    if [[ "$file" == *.flatpakref ]]; then
        flatpak install --user -y --noninteractive --from "$file" >/dev/null 2>&1 || fail "Flatpak couldn't install it."
    else
        flatpak install --user -y --noninteractive "$file" >/dev/null 2>&1 || fail "Flatpak couldn't install it."
    fi
    notify "$name is installed" "Open it from the launcher."
}

install_pacman() {
    local package
    package="$(bsdtar -xOf "$file" .PKGINFO 2>/dev/null | awk -F' = ' '$1=="pkgname"{print $2}')"
    name="${package:-$base}"
    notify "Installing $name..." "Enter your PIN or password when asked."
    pkexec pacman -U --noconfirm "$file" >/dev/null 2>&1 || fail "It couldn't be installed, or no password was entered."
    local desktop
    for desktop in $(pacman -Qlq "$package" 2>/dev/null | grep -E '^/usr/share/applications/[^/]+\.desktop$'); do
        manifest "$(basename "$desktop" .desktop)" pacman "package=$package"
    done
    notify "$name is installed" "Open it from the launcher."
}

case "${base,,}" in
    *.deb) install_deb ;;
    *.appimage) install_appimage ;;
    *.flatpakref | *.flatpak) install_flatpak ;;
    *.pkg.tar.zst | *.pkg.tar.xz) install_pacman ;;
    *) notify "Can't install $base" "Only .deb, AppImage, Flatpak and Arch package files can be installed." ; exit 1 ;;
esac
