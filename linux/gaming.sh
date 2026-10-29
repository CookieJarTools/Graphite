#!/usr/bin/env bash
# Sets this machine up for games: the graphics drivers for its GPU (with the 32-bit parts Steam
# and Proton need), Steam, the Modrinth App for Minecraft, GameMode (the CPU and GPU at
# full speed while a game runs), MangoHud (an FPS overlay), gamescope and power profiles.
# Minecraft gets settings against the stutter modpacks show: enough memory, fixed from the
# start, and garbage collection tuned for short pauses (Aikar's flags), under GameMode and on
# the discrete GPU. Graphite Desk's Settings runs this in a terminal ("Set up gaming"); run it
# again any time, it only adds what is missing. Real hardware: a VM has no GPU for games.
#
#   gaming.sh                    in a terminal, asks for the password as it goes
#   gaming.sh --from-installer   from the installer (as root, for the user in $GRAPHITE_USER,
#                                inside the new system, nothing started, nothing asked)
#   gaming.sh --background       from the Control Panel (as root through pkexec, for the user
#                                in $GRAPHITE_USER, nothing asked; its output goes to a log)
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

installing=false
quiet=false
if [ "${1:-}" = "--from-installer" ] || [ "${1:-}" = "--background" ]; then
    [ "$1" = "--from-installer" ] && installing=true
    quiet=true
    sudo() { "$@"; }        # already root
    USER="${GRAPHITE_USER:?the user to set up}"
    HOME="/home/$USER"
fi
start=(--now)
$installing && start=()

if ! $installing && [ "$(systemd-detect-virt || true)" != none ]; then
    echo "Note: This is a virtual machine. Games will run slowly without a real graphics card."
fi

say "Turning on 32-bit packages for Steam..."
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi
sudo pacman -Sy --noconfirm

packages=(steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope power-profiles-daemon
          flatpak pciutils linux-headers)

# The GPU's drivers (installer/gpu-packages.sh: the same list the installer uses).
mapfile -t gpu < <(bash "$here/installer/gpu-packages.sh")
nvidia=false
for package in "${gpu[@]}"; do
    if [ "$package" = "#nvidia" ]; then nvidia=true; else packages+=("$package"); fi
done
echo "Graphics found:"; lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' || echo "  (none reported)"

say "Installing ${#packages[@]} packages..."
sudo pacman -S --needed --noconfirm "${packages[@]}"

sudo systemctl enable "${start[@]}" power-profiles-daemon.service
getent group gamemode >/dev/null && sudo usermod -aG gamemode "$USER"

# NVIDIA on Wayland needs its kernel mode setting on (systemd-boot's entry, as the installer
# writes it), and Hyprland a few hints (hyprland.lua reads ~/.config/graphite/gpu).
if $nvidia; then
    say "Setting up NVIDIA for Wayland..."
    for entry in /boot/loader/entries/*.conf; do
        [ -f "$entry" ] || continue
        grep -q 'nvidia_drm.modeset=1' "$entry" || sudo sed -i 's/^options \(.*\)$/options \1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1/' "$entry"
    done
    mkdir -p "$HOME/.config/graphite"
    echo nvidia > "$HOME/.config/graphite/gpu"
    echo "Restart the computer when this finishes to load the NVIDIA driver."
fi

# Minecraft: the Modrinth App (from Flathub; it fetches the right Java for each version).
say "Installing the Modrinth App for Minecraft..."
sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install --system -y --noninteractive flathub com.modrinth.ModrinthApp || echo "The Modrinth App didn't install. Check your internet connection."

# Run as root (the installer, or the Control Panel in the background): what was written in the
# home is the person's.
if $quiet; then
    chown -R "$USER:$USER" "$HOME/.local" "$HOME/.config" 2>/dev/null || true
fi
$installing && exit 0

say "Done."
cat <<'DONE'
Steam: sign in, then in Settings > Compatibility turn on Steam Play for all titles (Proton).
For any game, set Launch Options to:  gamemoderun %command%    Add mangohud for an FPS counter.
Minecraft: open the Modrinth App and choose a modpack. For large modpacks, give it 6 to 8 GB of memory in its Settings.
DONE
if $nvidia; then echo "Restart now to load the NVIDIA driver."; fi
$quiet || read -rp "Press Enter to close."
