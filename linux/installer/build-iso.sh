#!/usr/bin/env bash
# Builds the Graphite Desk USB image: Arch's own install image (archiso's releng profile) with
# Graphite Desk's repository on it and its installer starting by itself: the graphical one
# (quickshell/installer.qml), or the text one (graphite-install.sh) without working graphics.
# Run as root on Arch Linux (the test VM will do), with the repository's path:
#
#   sudo bash linux/installer/build-iso.sh /mnt/StartMenu
#
# The image lands in linux/installer/out/. Write it to a USB stick with Rufus or balenaEtcher.
set -euo pipefail
repo="$(cd "${1:?give the path of the repository}" && pwd)"
out="$repo/linux/installer/out"
work=/var/tmp/graphite-iso
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)."; exit 1; }

pacman -S --needed --noconfirm archiso git

# A build stopped halfway can leave the system's /dev and the like mounted inside its folder:
# unmount those first, and never let rm cross into a mount.
clean() {
    { findmnt -rno TARGET | grep "^$work/" || true; } | sort -r | xargs -r -n1 umount -l
    rm -rf --one-file-system "$work"
}
clean
mkdir -p "$work" "$out"
cp -r /usr/share/archiso/configs/releng "$work/profile"
profile="$work/profile"

# Its name, on the stick and in the boot menu.
sed -i \
    -e 's/^iso_name=.*/iso_name="graphite-desk"/' \
    -e 's/^iso_label=.*/iso_label="GRAPHITE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
    -e 's/^iso_publisher=.*/iso_publisher="Graphite Desk"/' \
    -e 's/^iso_application=.*/iso_application="Graphite Desk installer"/' \
    "$profile/profiledef.sh"
grep -rl "Arch Linux install medium" "$profile" | xargs -r sed -i 's/Arch Linux install medium/Graphite Desk installer/g'

# What the installer needs on top of Arch's own image: its screens (Hyprland and Quickshell,
# with Graphite's fonts, icons and pointer), NetworkManager for Wi-Fi (so the network joined
# here goes into the new system), and the text installer's dialog as a fallback.
printf '%s\n' dialog terminus-font sudo hyprland quickshell qt6-wayland qt6-svg mesa \
    inter-font noto-fonts ttf-jetbrains-mono papirus-icon-theme capitaine-cursors \
    networkmanager nvidia-open nvidia-utils egl-wayland >> "$profile/packages.x86_64"

# NVIDIA cards (RTX 20 series and newer) run the installer's screens on NVIDIA's own driver:
# nouveau, the open-source one, can't drive recent cards and is kept out (elsewhere it's never
# used, so this changes nothing on other machines).
grep -rl 'archisobasedir=' "$profile/efiboot" "$profile/grub" "$profile/syslinux" 2>/dev/null | \
    xargs -r sed -i 's/archisobasedir=%INSTALL_DIR%/& modprobe.blacklist=nouveau nvidia_drm.modeset=1 nvidia_drm.fbdev=1/'

# NetworkManager instead of the stock image's iwd and systemd-networkd.
wants="$profile/airootfs/etc/systemd/system"
rm -f "$wants/multi-user.target.wants/iwd.service" "$wants/multi-user.target.wants/systemd-networkd.service" \
    "$wants/sockets.target.wants/systemd-networkd.socket" "$wants/network-online.target.wants/systemd-networkd-wait-online.service" \
    "$wants/systemd-networkd-wait-online.service.wants/"* 2>/dev/null || true
mkdir -p "$wants/multi-user.target.wants" "$wants/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$wants/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$wants/dbus-org.freedesktop.NetworkManager.service"
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service "$wants/network-online.target.wants/NetworkManager-wait-online.service"

# The "live" user, made at start-up (it may run sudo without a password: the stick is for
# installing) and signed in on the first screen, where its login opens the installer.
cat > "$wants/graphite-live-user.service" <<'UNIT'
[Unit]
Description=The Graphite Desk installer's user
Before=systemd-user-sessions.service getty@tty1.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'id live >/dev/null 2>&1 || { useradd -m -G wheel,video,input -s /bin/bash live && passwd -d live; }'

[Install]
WantedBy=multi-user.target
UNIT
ln -sf ../graphite-live-user.service "$wants/multi-user.target.wants/graphite-live-user.service"
mkdir -p "$profile/airootfs/etc/sudoers.d"
echo 'live ALL=(ALL:ALL) NOPASSWD: ALL' > "$profile/airootfs/etc/sudoers.d/live"
sed -i 's/--autologin root/--autologin live/' "$wants/getty@tty1.service.d/autologin.conf"
mkdir -p "$profile/airootfs/etc/skel"
cat > "$profile/airootfs/etc/skel/.bash_profile" <<'PROFILE'
# On the Graphite Desk USB stick: the installer opens on the first screen.
[ -f ~/.bashrc ] && . ~/.bashrc
if [ "$(tty)" = /dev/tty1 ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    graphite-install-gui
fi
PROFILE

# Graphite Desk's repository as committed (a clean clone: Unix line endings, none of the test
# VM, nothing built), its git history with it and its origin pointing at GitHub, so the
# installed copy can pull updates and push changes. Commit before building.
git config --global --add safe.directory "$repo"
git clone --quiet --no-local "$repo" "$profile/airootfs/usr/share/graphite-desk"
origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
[ -n "$origin" ] && git -C "$profile/airootfs/usr/share/graphite-desk" remote set-url origin "$origin"
echo "Graphite Desk at $(git -C "$repo" log --oneline -1)"
# GRAPHITE_FROM_WORKTREE=1: for trying changes before committing them, the working folder's
# files (changed and new ones, as git sees them) go over the commit.
if [ -n "${GRAPHITE_FROM_WORKTREE:-}" ]; then
    clone="$profile/airootfs/usr/share/graphite-desk"
    git -C "$repo" ls-files -d -z | (cd "$clone" && xargs -0 -r rm -f)
    git -C "$repo" ls-files -co --exclude-standard -z | tar -C "$repo" --null --ignore-failed-read -T - -cf - 2>/dev/null | tar -C "$clone" -xf -
    echo "  with the working folder's changes"
fi

cat > "$profile/airootfs/usr/local/bin/graphite-install" <<'START'
#!/usr/bin/env bash
# Starts the Graphite Desk installer, in a font big enough to read, with the kernel's messages
# kept off its screens.
setfont ter-v24b 2>/dev/null
dmesg -n 1 2>/dev/null
exec bash /usr/share/graphite-desk/linux/installer/graphite-install.sh "$@"
START

cat > "$profile/airootfs/usr/local/bin/graphite-install-gui" <<'START'
#!/usr/bin/env bash
# Opens the installer's screens (quickshell/installer.qml in its own Hyprland, installer/gui.lua);
# when they can't show (no working graphics), the text installer instead.
sudo dmesg -n 1 2>/dev/null
rm -f /tmp/graphite-gui-closed
start-hyprland -- --config /usr/share/graphite-desk/linux/installer/gui.lua > /tmp/graphite-gui.log 2>&1
if [ ! -f /tmp/graphite-gui-closed ]; then
    echo "The installer's screens couldn't start; here is the text installer instead."
    sleep 2
    sudo graphite-install
fi
echo "The installer closed. Type graphite-install-gui (or sudo graphite-install) to start it again."
START

sed -i 's|^file_permissions=(|file_permissions=(\n  ["/usr/local/bin/graphite-install"]="0:0:755"\n  ["/usr/local/bin/graphite-install-gui"]="0:0:755"\n  ["/etc/sudoers.d/live"]="0:0:440"|' "$profile/profiledef.sh"

# Made inside the build folder, then copied out: big writes to a VM's shared folder can fail.
mkarchiso -v -w "$work/work" -o "$work/out" "$profile"
# Named for the hour it was made, so an older image a test VM still has open can stay.
for image in "$work/out"/*.iso; do
    name="$(basename "$image" -x86_64.iso)-$(date +%H%M)-x86_64.iso"
    rm -f "$out"/graphite-desk-*.iso 2>/dev/null || true
    cp "$image" "$out/$name"
done
clean
chown -R --reference="$repo" "$out"
ls -lh "$out"
