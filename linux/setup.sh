#!/usr/bin/env bash
# Sets up Graphite Desk in an Arch Linux VM (VMware): installs Hyprland, Quickshell and what
# the shell uses, starts the services, and links the configs to this checkout, so the shell
# runs straight from the repo. Run it as your normal user (it asks for sudo):
#
#   bash /mnt/hgfs/StartMenu/linux/setup.sh
#
# Safe to run again: packages already there are skipped, existing configs are moved aside
# to *.bak once.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

packages=(
    # The desktop
    hyprland quickshell qt6-wayland qt6-svg xdg-desktop-portal-hyprland hyprpolkitagent hyprlock
    # Look
    papirus-icon-theme adwaita-icon-theme inter-font ttf-jetbrains-mono
    # Sound, network, Bluetooth (the quick settings panel)
    pipewire wireplumber pipewire-pulse networkmanager bluez bluez-utils
    # Apps to test with
    kitty nautilus firefox libnotify
    # VMware guest tools: shared folders, clipboard, resizing with the VM window
    open-vm-tools gtkmm3
)

echo "Installing packages..."
sudo pacman -Syu --needed --noconfirm "${packages[@]}"

echo "Starting services..."
sudo systemctl enable --now NetworkManager.service bluetooth.service vmtoolsd.service vmware-vmblock-fuse.service

# The VM's shared folders (this checkout among them) mounted at every start, not just today.
if ! grep -q "vmhgfs-fuse" /etc/fstab; then
    echo "Mounting VMware shared folders at /mnt/hgfs on every start..."
    sudo mkdir -p /mnt/hgfs
    echo ".host:/ /mnt/hgfs fuse.vmhgfs-fuse defaults,allow_other,nofail 0 0" | sudo tee -a /etc/fstab >/dev/null
fi

link() {
    local target="$1" link="$2"
    mkdir -p "$(dirname "$link")"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        echo "Keeping your $link as $link.bak"
        mv "$link" "$link.bak"
    fi
    ln -sfn "$target" "$link"
    echo "Linked $link -> $target"
}

link "$here/quickshell" "$HOME/.config/quickshell/graphite"
link "$here/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"

cat <<'DONE'

Done. Log in on the console and start the desktop with:

    start-hyprland

Super opens the launcher, Alt+Tab switches windows, Super+Enter opens a terminal.
Try a notification with:  notify-send "Hello" "From Graphite Desk"
DONE
