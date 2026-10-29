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
#   .tar.gz, .tar.xz, .zip of a ready-made Linux build (from GitHub: github.sh)
#                     unpacked into ~/Applications/NAME, its program given a launcher entry
#                     (and a command, in ~/.local/bin, when it's one for the terminal)
#
# github.sh passes GRAPHITE_APP_NAME and GRAPHITE_APP_ICON (the project's name and its
# owner's picture), used when the app doesn't bring its own.
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
            archive)
                rm -rf "$path"
                rm -f "$applications/$id.desktop" ${command:+"$command"}
                [[ "$icon" == /* ]] && rm -f "$icon"
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
    id="appimage-$(printf '%s' "$base" | sed -E 's/\.appimage$//I' | tr -c 'A-Za-z0-9._-' '-' | tr 'A-Z' 'a-z')"
    notify "Installing $base..."
    work="$(mktemp -d)"
    ( cd "$work" && "$target" --appimage-extract '*.desktop' >/dev/null 2>&1 && "$target" --appimage-extract .DirIcon >/dev/null 2>&1 )
    entry="$(find "$work/squashfs-root" -maxdepth 1 -name '*.desktop' 2>/dev/null | head -1)"
    icon_file="$(readlink -f "$work/squashfs-root/.DirIcon" 2>/dev/null || true)"
    icon="$HOME/.local/share/icons/$id.png"
    mkdir -p "$(dirname "$icon")"
    if [ -f "$icon_file" ]; then cp -f "$icon_file" "$icon"
    elif [ -f "${GRAPHITE_APP_ICON:-}" ]; then cp -f "$GRAPHITE_APP_ICON" "$icon"
    else icon="application-x-executable"; fi
    if [ -n "$entry" ]; then
        name="$(grep -m1 '^Name=' "$entry" | cut -d= -f2-)"
        sed -e "s|^Exec=[^ ]*|Exec=\"$target\"|" -e "s|^Icon=.*|Icon=$icon|" -e '/^TryExec=/d' "$entry" > "$applications/$id.desktop"
    else
        name="${GRAPHITE_APP_NAME:-$(printf '%s' "$base" | sed -E 's/\.appimage$//I')}"
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

# A ready-made build in an archive: unpacked into ~/Applications, its program found (the one the
# build's own launcher entry names, else the one named like the app, else its biggest program at
# the top or in bin), and given a launcher entry; a terminal program also becomes a command.
install_archive() {
    local folder="$HOME/Applications" stem id target inner entry program icon command="" terminal=false
    stem="$(basename "$base" | sed -E 's/\.(tar\.gz|tgz|tar\.xz|tar\.bz2|zip)$//I')"
    name="${GRAPHITE_APP_NAME:-$stem}"
    id="app-$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-' | tr 'A-Z' 'a-z')"
    target="$folder/$name"
    notify "Installing $name..."
    rm -rf "$target"
    mkdir -p "$target"
    bsdtar -xf "$file" -C "$target" 2>/dev/null || { rm -rf "$target"; fail "$base couldn't be unpacked."; }
    # One folder inside it: that folder is the app.
    inner="$(find "$target" -mindepth 1 -maxdepth 1)"
    if [ "$(printf '%s\n' "$inner" | grep -c .)" = 1 ] && [ -d "$inner" ]; then
        find "$inner" -mindepth 1 -maxdepth 1 -exec mv -t "$target" {} +
        rmdir "$inner"
    fi

    entry="$(find "$target" -maxdepth 4 -name '*.desktop' -path '*applications*' 2>/dev/null | head -1)"
    [ -n "$entry" ] || entry="$(find "$target" -maxdepth 2 -name '*.desktop' 2>/dev/null | head -1)"
    if [ -n "$entry" ]; then
        local named
        named="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$entry" | head -1 | tr -d '"')"
        program="$(find "$target" -maxdepth 3 -type f -name "$(basename "$named")" -perm -u+x 2>/dev/null | head -1)"
        grep -q -i '^Terminal=true' "$entry" && terminal=true
    fi
    if [ -z "${program:-}" ]; then
        # Programs, not libraries or helpers: runnable files at the top or in bin.
        local candidates
        candidates="$(find "$target" "$target/bin" -maxdepth 1 -type f -perm -u+x 2>/dev/null \
            | grep -v -E '/(lib|.*\.so(\..*)?|chrome-sandbox|chrome_crashpad_handler|crashpad_handler|.*[-_]helper.*|uninstall.*|.*\.(sh|py|txt|md|json))$' || true)"
        program="$(printf '%s\n' "$candidates" | grep -i -E "/$(printf '%s' "$name" | tr 'A-Z' 'a-z' | cut -c1-4)[^/]*$" | head -1)"
        [ -n "$program" ] || program="$(printf '%s\n' "$candidates" | grep . | xargs -r -d '\n' ls -S 2>/dev/null | head -1)"
    fi
    [ -n "$program" ] || { rm -rf "$target"; fail "There's no program in $base to open."; }

    # A window of its own, or the terminal: what it's built on says (with no launcher entry).
    if [ -z "$entry" ] && ! ldd "$program" 2>/dev/null | grep -q -E 'lib(gtk|Qt|X11|xcb|wayland-client|EGL|GL|nss3|SDL)'; then
        terminal=true
    fi
    if $terminal; then
        mkdir -p "$HOME/.local/bin"
        command="$HOME/.local/bin/$(basename "$program")"
        ln -sfn "$program" "$command"
    fi

    icon="$HOME/.local/share/icons/$id.png"
    mkdir -p "$(dirname "$icon")"
    local own_icon="" icon_name=""
    [ -n "$entry" ] && icon_name="$(sed -n 's/^Icon=//p' "$entry" | head -1)"
    [ -n "$icon_name" ] && own_icon="$(find "$target" \( -name "$icon_name.png" -o -name "$icon_name.svg" -o -path "*/$icon_name" \) -type f 2>/dev/null | sort -r | head -1)"
    if [ -n "$own_icon" ]; then
        icon="$HOME/.local/share/icons/$id.${own_icon##*.}"
        cp -f "$own_icon" "$icon"
    elif [ -f "${GRAPHITE_APP_ICON:-}" ]; then cp -f "$GRAPHITE_APP_ICON" "$icon"
    else icon="application-x-executable"; fi

    if [ -n "$entry" ]; then
        sed -e "s|^Exec=[^ ]*|Exec=\"$program\"|" -e "s|^Icon=.*|Icon=$icon|" -e '/^TryExec=/d' "$entry" > "$applications/$id.desktop"
        name="$(grep -m1 '^Name=' "$entry" | cut -d= -f2-)"
    else
        printf '[Desktop Entry]\nType=Application\nName=%s\nExec="%s"\nIcon=%s\nTerminal=%s\n' "$name" "$program" "$icon" "$terminal" > "$applications/$id.desktop"
    fi
    manifest "$id" archive "path=\"$target\"" "icon=\"$icon\"" "command=\"$command\""
    if [ -n "$command" ]; then
        notify "$name is installed" "Open it from the launcher, or type $(basename "$command") in the terminal."
    else
        notify "$name is installed" "Open it from the launcher."
    fi
}

case "${base,,}" in
    *.deb) install_deb ;;
    *.appimage) install_appimage ;;
    *.flatpakref | *.flatpak) install_flatpak ;;
    *.pkg.tar.zst | *.pkg.tar.xz) install_pacman ;;
    *.tar.gz | *.tgz | *.tar.xz | *.tar.bz2 | *.zip) install_archive ;;
    *) notify "Can't install $base" "Only .deb, AppImage, Flatpak and Arch package files can be installed." ; exit 1 ;;
esac
