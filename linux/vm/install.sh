#!/usr/bin/env bash
# Unattended install of the Graphite Desk test VM, run in the Arch Linux live ISO by
# cloud-init (user-data). Wipes the VM's one disk, installs Arch with Hyprland, Quickshell
# and what the shell uses, signs the user in automatically and starts the desktop, with the
# shell running straight from the Windows checkout (VMware shared folder "StartMenu").
#
# vm.env, next to this script on the CIDATA disc, gives USER_NAME, PASSWORD_HASH (crypt),
# HOST_NAME, TIME_ZONE, LOCALE and KEYMAP. The log stays at /root/graphite-install.log in
# the new system.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$here/vm.env"
log=/root/graphite-install.log
exec > >(tee -a "$log") 2>&1

echo "== Graphite Desk VM install, $(date) =="

# The disk: the one fixed, non-removable disk.
disk="$(lsblk -dpno NAME,TYPE,RM | awk '$2 == "disk" && $3 == "0" { print $1; exit }')"
if [ -z "$disk" ]; then
    echo "No disk found"
    exit 1
fi
part() { if [[ "$disk" == *nvme* ]]; then echo "${disk}p$1"; else echo "${disk}$1"; fi; }
echo "Installing to $disk"

echo "Waiting for the network..."
until curl -s --max-time 5 -o /dev/null https://archlinux.org; do sleep 3; done
timedatectl set-ntp true
systemctl start pacman-init.service # the live ISO's keyring

echo "Partitioning..."
sgdisk --zap-all "$disk"
sgdisk -n1:0:+1G -t1:ef00 -c1:EFI -n2:0:0 -t2:8304 -c2:root "$disk"
partprobe "$disk"
sleep 2
mkfs.fat -F32 "$(part 1)"
mkfs.ext4 -F "$(part 2)"
mount "$(part 2)" /mnt
mount --mkdir "$(part 1)" /mnt/boot

echo "Installing packages..."
packages=(
    base linux linux-firmware sudo nano man-db
    # The desktop
    hyprland quickshell qt6-wayland qt6-svg xdg-desktop-portal-hyprland hyprpolkitagent hyprlock mesa
    # Look
    papirus-icon-theme adwaita-icon-theme capitaine-cursors inter-font ttf-jetbrains-mono dconf
    # Apps' saved sign-ins (system/session.sh)
    gnome-keyring
    # Sound, network, Bluetooth
    pipewire wireplumber pipewire-pulse networkmanager network-manager-applet bluez bluez-utils
    # The Control Panel's helpers: idle, night light, brightness, update checks, firewall, printers
    hypridle hyprsunset brightnessctl pacman-contrib ufw cups cups-pk-helper system-config-printer avahi nss-mdns
    # Apps to test with
    kitty nautilus firefox libnotify loupe celluloid papers slurp wl-clipboard xdg-user-dirs udisks2 gvfs exfatprogs ntfs-3g dosfstools
    # The login screen (Graphite's greeter, run by greetd)
    greetd
    # Installing apps by opening the download: Ubuntu apps in a container, AppImages, Flatpak
    distrobox podman flatpak fuse2 gnome-software xdg-utils desktop-file-utils
    # Checks from the host: screenshots, typing and the pointer from inside
    grim wtype ydotool
)
# The VM software's guest tools: shared folders, clipboard, resizing with the window. Where
# the checkout shows up: VirtualBox mounts the "StartMenu" share itself (make-vm.ps1 sets
# /mnt/StartMenu); VMware's shares are mounted from fstab under /mnt/hgfs.
case "$(systemd-detect-virt)" in
    oracle)
        packages+=(virtualbox-guest-utils)
        guest_services="vboxservice.service"
        share=/mnt/StartMenu
        ;;
    vmware)
        packages+=(open-vm-tools gtkmm3)
        guest_services="vmtoolsd.service vmware-vmblock-fuse.service"
        share=/mnt/hgfs/StartMenu
        ;;
    *)
        guest_services=""
        share=/mnt/StartMenu
        ;;
esac
pacstrap -K /mnt "${packages[@]}"

genfstab -U /mnt >> /mnt/etc/fstab
if [ "$share" = /mnt/hgfs/StartMenu ]; then
    mkdir -p /mnt/mnt/hgfs
    echo ".host:/ /mnt/hgfs fuse.vmhgfs-fuse defaults,allow_other,nofail 0 0" >> /mnt/etc/fstab
fi

root_partuuid="$(blkid -s PARTUUID -o value "$(part 2)")"
cp "$here/vm.env" /mnt/root/vm.env
cp "$here/greetd-setup.sh" /mnt/root/greetd-setup.sh
{
    echo "GUEST_SERVICES='$guest_services'"
    echo "SHARE='$share'"
} >> /mnt/root/vm.env

cat > /mnt/root/configure.sh <<'CONFIGURE'
#!/usr/bin/env bash
set -euo pipefail
source /root/vm.env

ln -sf "/usr/share/zoneinfo/$TIME_ZONE" /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOST_NAME" > /etc/hostname

useradd -m -G wheel -s /bin/bash "$USER_NAME"
usermod -p "$PASSWORD_HASH" "$USER_NAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Boot: systemd-boot, straight into Arch.
bootctl install --esp-path=/boot
cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 0
LOADER
cat > /boot/loader/entries/arch.conf <<ENTRY
title Arch Linux (Graphite Desk)
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$ROOT_PARTUUID rw quiet
ENTRY

# shellcheck disable=SC2086 # one or two service names
systemctl enable NetworkManager.service bluetooth.service $GUEST_SERVICES
# VirtualBox's shared folders belong to the vboxsf group.
if getent group vboxsf >/dev/null; then usermod -aG vboxsf "$USER_NAME"; fi
# VirtualBox's guest control (VBoxManage guestcontrol, for checks from Windows) signs in
# through PAM as "vboxservice"; Arch ships no rules for it, so every sign-in was refused.
if [ -n "$GUEST_SERVICES" ] && [ "${GUEST_SERVICES#vboxservice}" != "$GUEST_SERVICES" ]; then
    cat > /etc/pam.d/vboxservice <<'PAM'
#%PAM-1.0
auth      include   system-auth
account   include   system-auth
session   include   system-auth
PAM
fi

# Graphite's login screen at start (greetd), reading Graphite Desk from the shared folder.
bash /root/greetd-setup.sh "$SHARE/linux" gb

home="/home/$USER_NAME"

# The shell and Hyprland's config, straight from the Windows checkout.
mkdir -p "$home/.config/quickshell" "$home/.config/hypr"
ln -sfn "$SHARE/linux/quickshell" "$home/.config/quickshell/graphite"
ln -sfn "$SHARE/linux/hypr/hyprland.lua" "$home/.config/hypr/hyprland.lua"
chown -R "$USER_NAME:$USER_NAME" "$home"
CONFIGURE

echo "ROOT_PARTUUID=$root_partuuid" >> /mnt/root/vm.env
arch-chroot /mnt bash /root/configure.sh
rm /mnt/root/configure.sh /mnt/root/vm.env /mnt/root/greetd-setup.sh

echo "== Done, $(date). Switching off; make-vm.ps1 takes the discs out and starts the new system. =="
cp "$log" /mnt/root/graphite-install.log
umount -R /mnt
systemctl poweroff
