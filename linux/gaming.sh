#!/usr/bin/env bash
# Sets this machine up for games: the graphics drivers for its GPU (with the 32-bit parts Steam
# and Proton need), Steam, Prism Launcher for Minecraft with Java, GameMode (the CPU and GPU at
# full speed while a game runs), MangoHud (an FPS overlay), gamescope and power profiles.
# Minecraft gets settings against the stutter modpacks show: enough memory, fixed from the
# start, and garbage collection tuned for short pauses (Aikar's flags), under GameMode and on
# the discrete GPU. Graphite Desk's Settings runs this in a terminal ("Set up gaming"); run it
# again any time, it only adds what is missing. Real hardware: a VM has no GPU for games.
set -euo pipefail

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [ "$(systemd-detect-virt || true)" != none ]; then
    echo "Note: this is a virtual machine; games need a real GPU, so expect them to be slow here."
fi

say "Turning on 32-bit packages (multilib), which Steam needs..."
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi
sudo pacman -Sy --noconfirm

packages=(steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope power-profiles-daemon
          prismlauncher jre21-openjdk jre17-openjdk jre8-openjdk vulkan-icd-loader lib32-vulkan-icd-loader
          mesa lib32-mesa pciutils)

# The GPU's drivers.
gpus="$(lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' || true)"
nvidia=false
if grep -qi nvidia <<<"$gpus"; then
    nvidia=true
    packages+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings linux-headers libva-nvidia-driver)
fi
grep -qiE 'AMD|ATI|Radeon' <<<"$gpus" && packages+=(vulkan-radeon lib32-vulkan-radeon libva-mesa-driver)
grep -qi intel <<<"$gpus" && packages+=(vulkan-intel lib32-vulkan-intel intel-media-driver)
echo "Graphics found:"; echo "${gpus:-  (none reported)}"

say "Installing ${#packages[@]} packages..."
sudo pacman -S --needed --noconfirm "${packages[@]}"

sudo systemctl enable --now power-profiles-daemon.service
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
    echo "Restart the computer once this finishes, for the NVIDIA driver to load."
fi

# Minecraft (Prism Launcher): half the memory, between 4 and 12 GB, fixed from the start;
# short-pause garbage collection; GameMode; the discrete GPU; Java fetched per Minecraft version.
prism="$HOME/.local/share/PrismLauncher/prismlauncher.cfg"
if [ ! -f "$prism" ]; then
    say "Setting up Prism Launcher for smooth modpacks..."
    total_mb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
    memory=$(( total_mb / 2 ))
    [ "$memory" -gt 12288 ] && memory=12288
    [ "$memory" -lt 4096 ] && memory=4096
    flags="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseIntervalPercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1"
    mkdir -p "$(dirname "$prism")"
    cat > "$prism" <<PRISM
[General]
MinMemAlloc=$memory
MaxMemAlloc=$memory
JvmArgs=$flags
EnableFeralGamemode=true
UseDiscreteGpu=true
AutomaticJavaSwitch=true
AutomaticJavaDownload=true
PRISM
    echo "Minecraft gets ${memory} MB."
fi

say "Done."
cat <<'DONE'
Steam: sign in, then in Settings > Compatibility turn on Steam Play for all titles (Proton).
For any game, Launch Options:  gamemoderun %command%    (add mangohud for an FPS counter)
Minecraft: open Prism Launcher and add your modpack; it is already tuned.
DONE
if $nvidia; then echo "Restart now to load the NVIDIA driver."; fi
read -rp "Press Enter to close."
