#!/usr/bin/env bash
# The Graphite Desk installer: puts Arch Linux with Graphite Desk on this computer, asking only
# what it has to in plain screens: the network (Wi-Fi, when there is no cable), the disk to
# use (all of it: everything on it is erased, after typing ERASE), the person's name and
# password, the time zone and keyboard, and whether to set up gaming. Then it installs, with a
# progress bar, and restarts into Graphite's login screen.
#
# It runs from the Graphite Desk USB stick (build-iso.sh makes it), which starts it by itself;
# Graphite Desk's repository (with its git history) is on the stick in /usr/share/graphite-desk
# and goes to /opt/graphite-desk, owned by the person: they can change it, pull updates and
# push, and the login screen can still read it. The log is /tmp/graphite-install.log, copied
# into the new system.
#
#   GRAPHITE_ANSWERS=file graphite-install   answers instead of questions (for testing):
#       DISK, FULL_NAME, USER_NAME, PASSWORD, TIME_ZONE, KEYBOARD, GAMING (yes|no)
set -uo pipefail

source_dir=/usr/share/graphite-desk
target=/mnt
log=/tmp/graphite-install.log
export DIALOGRC=/usr/share/graphite-desk/linux/installer/dialogrc
title="Graphite Desk"
backtitle="Graphite Desk installer"

ask() { dialog --backtitle "$backtitle" --title "$title" --stdout "$@"; }
say() { dialog --backtitle "$backtitle" --title "$title" --msgbox "$1" "${2:-9}" 64; }
fail() {
    dialog --backtitle "$backtitle" --title "Something went wrong" --msgbox "$1\n\nThe details are in $log. Restart to try again; nothing on the computer has been changed unless it says so above." 13 70
    exit 1
}

if [ -n "${GRAPHITE_ANSWERS:-}" ]; then
    # shellcheck disable=SC1090
    source "$GRAPHITE_ANSWERS"
fi

# ---------- the computer ----------

if [ ! -d /sys/firmware/efi ]; then
    say "This computer started the installer the old way (BIOS).\n\nRestart, open the boot menu (often F12, F11 or Esc), and choose the USB stick's entry that says UEFI." 11
    exit 1
fi

# ---------- the network ----------

online() { curl -s --max-time 5 -o /dev/null https://archlinux.org; }

connect_wifi() {
    local device networks ssid password
    device="$(iwctl device list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/station/ {print $1; exit}')"
    if [ -z "$device" ]; then
        say "There's no internet, and no Wi-Fi was found.\n\nPlug in a network cable, then press Enter." 10
        return
    fi
    iwctl station "$device" scan >/dev/null 2>&1
    sleep 4
    mapfile -t networks < <(iwctl station "$device" get-networks 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | tail -n +5 | sed 's/^[ >]*//' | awk 'NF {sub(/ +(psk|open|8021x) +.*$/, ""); print}' | grep -v '^$')
    if [ ${#networks[@]} -eq 0 ]; then
        say "No Wi-Fi networks were found nearby.\n\nPlug in a network cable, or move closer to the router, then press Enter." 10
        return
    fi
    local items=()
    for ssid in "${networks[@]}"; do items+=("$ssid" ""); done
    ssid="$(ask --menu "Choose your Wi-Fi network:" 18 64 10 "${items[@]}")" || return
    password="$(ask --insecure --passwordbox "Password for \"$ssid\":" 9 64)" || return
    iwctl --passphrase "$password" station "$device" connect "$ssid" >>"$log" 2>&1
    sleep 6
}

until online; do
    connect_wifi
done

# ---------- the disk ----------

if [ -z "${DISK:-}" ]; then
    # Every disk but the USB stick this runs from.
    live="$(lsblk -no PKNAME "$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null)" 2>/dev/null | head -1)"
    items=()
    while read -r name size model; do
        [ "/dev/$live" = "$name" ] && continue
        note="$size ${model:-disk}"
        if lsblk -no FSTYPE "$name" | grep -q ntfs; then note="$note  (has Windows)"; fi
        items+=("$name" "$note")
    done < <(lsblk -dpno NAME,SIZE,MODEL -e 7,11 | awk '{name=$1; size=$2; $1=$2=""; sub(/^ +/, ""); print name, size, $0}')
    [ ${#items[@]} -gt 0 ] || fail "No disk was found to install on."
    DISK="$(ask --menu "Which disk should Graphite Desk go on?\n\nEverything on it will be erased." 16 72 6 "${items[@]}")" || exit 1
    disk_note="$(lsblk -dno SIZE,MODEL "$DISK" | xargs)"
    ask --defaultno --yesno "Everything on this disk will be erased:\n\n    $DISK  ($disk_note)\n\nWindows, files, photos: all of it, for good.\n\nErase it and install Graphite Desk?" 14 64 || exit 1
    confirm="$(ask --inputbox "To be sure, type ERASE (in capitals):" 9 64)" || exit 1
    [ "$confirm" = "ERASE" ] || { say "Nothing was erased. Restart to begin again."; exit 1; }
fi

# ---------- the person ----------

if [ -z "${FULL_NAME:-}" ]; then
    FULL_NAME="$(ask --inputbox "What's your name?" 9 64)" || exit 1
    suggested="$(echo "${FULL_NAME%% *}" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
    while true; do
        USER_NAME="$(ask --inputbox "A short name for signing in (small letters and numbers):" 9 64 "${suggested:-me}")" || exit 1
        [[ "$USER_NAME" =~ ^[a-z][a-z0-9_-]{0,30}$ ]] && break
        say "Use small letters and numbers, starting with a letter."
    done
    while true; do
        PASSWORD="$(ask --insecure --passwordbox "Choose a password:" 9 64)" || exit 1
        again="$(ask --insecure --passwordbox "Type it again:" 9 64)" || exit 1
        if [ -z "$PASSWORD" ]; then say "The password can't be empty."; continue; fi
        [ "$PASSWORD" = "$again" ] && break
        say "Those two didn't match. Try again."
    done
fi

if [ -z "${TIME_ZONE:-}" ]; then
    guess="$(curl -s --max-time 5 https://ipapi.co/timezone 2>/dev/null)"
    [ -f "/usr/share/zoneinfo/$guess" ] || guess="Europe/London"
    if ask --yesno "Your time zone looks like:\n\n    $guess\n\nIs that right?" 10 64; then
        TIME_ZONE="$guess"
    else
        items=()
        while read -r zone; do items+=("$zone" ""); done < <(timedatectl list-timezones)
        TIME_ZONE="$(ask --menu "Choose your time zone:" 20 64 12 "${items[@]}")" || TIME_ZONE="$guess"
    fi
fi

# Keyboards: the layout's name for the desktop, and for the text console.
declare -A console=([gb]=uk [us]=us [ie]=uk [de]=de-latin1 [fr]=fr-latin1 [es]=es [it]=it [nl]=nl [se]=sv-latin1 [no]=no-latin1 [dk]=dk-latin1 [fi]=fi [pl]=pl [pt]=pt-latin1 [br]=br-abnt2 [ch]=de_CH-latin1 [be]=be-latin1)
if [ -z "${KEYBOARD:-}" ]; then
    KEYBOARD="$(ask --default-item gb --menu "Your keyboard:" 20 64 12 \
        gb "English (UK)" us "English (US)" ie "English (Ireland)" de "German" fr "French" es "Spanish" \
        it "Italian" nl "Dutch" se "Swedish" no "Norwegian" dk "Danish" fi "Finnish" pl "Polish" \
        pt "Portuguese" br "Portuguese (Brazil)" ch "Swiss" be "Belgian")" || KEYBOARD=gb
fi
locale="en_US.UTF-8"
case "$KEYBOARD" in gb | ie) locale="en_GB.UTF-8" ;; esac

if [ -z "${GAMING:-}" ]; then
    if ask --yesno "Set it up for games too?\n\nSteam, Minecraft (Prism Launcher, tuned for modpacks), GameMode and an FPS counter. You can also do this later from Settings." 11 64; then
        GAMING=yes
    else
        GAMING=no
    fi
fi

summary="Disk:      $DISK  (will be erased)\nName:      $FULL_NAME  ($USER_NAME)\nTime zone: $TIME_ZONE\nKeyboard:  $KEYBOARD\nGaming:    $GAMING"
if [ -z "${GRAPHITE_ANSWERS:-}" ]; then
    ask --yes-label "Install" --no-label "Cancel" --yesno "Ready to install:\n\n$summary\n\nThis takes 10 to 30 minutes, depending on the internet." 15 70 || exit 1
fi

# ---------- installing ----------

part() { if [[ "$DISK" =~ [0-9]$ ]]; then echo "${DISK}p$1"; else echo "${DISK}$1"; fi; }

cpu_microcode() {
    if grep -q GenuineIntel /proc/cpuinfo; then echo intel-ucode; elif grep -q AuthenticAMD /proc/cpuinfo; then echo amd-ucode; fi
}

# The steps, each moving the bar; the output goes to the log.
install_steps() {
    step() { printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2"; }

    step 2 "Preparing the disk..."
    umount -R "$target" >>"$log" 2>&1
    wipefs -af "$DISK" >>"$log" 2>&1
    sgdisk --zap-all "$DISK" >>"$log" 2>&1
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot -n 2:0:0 -t 2:8300 -c 2:graphite "$DISK" >>"$log" 2>&1 || { echo "disk" > /tmp/graphite-failed; return; }
    partprobe "$DISK" >>"$log" 2>&1; sleep 2
    mkfs.fat -F 32 -n BOOT "$(part 1)" >>"$log" 2>&1
    mkfs.ext4 -F -L graphite "$(part 2)" >>"$log" 2>&1 || { echo "format" > /tmp/graphite-failed; return; }
    mount "$(part 2)" "$target" && mount --mkdir "$(part 1)" "$target/boot" || { echo "mount" > /tmp/graphite-failed; return; }

    step 6 "Turning on 32-bit packages and the fastest mirrors..."
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    pacman -Sy --noconfirm >>"$log" 2>&1

    local packages=(
        base linux linux-firmware linux-headers sudo nano man-db $(cpu_microcode)
        networkmanager bluez bluez-utils pipewire wireplumber pipewire-pulse pipewire-alsa
        hyprland quickshell qt6-wayland qt6-svg xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
        greetd papirus-icon-theme adwaita-icon-theme capitaine-cursors inter-font ttf-jetbrains-mono noto-fonts noto-fonts-emoji dconf
        kitty nautilus firefox libnotify grim
        distrobox podman flatpak fuse2 gnome-software xdg-utils desktop-file-utils
        power-profiles-daemon zram-generator pciutils git
    )
    # Installed into a virtual machine: its tools (shared clipboard, resizing with the window).
    local guest_services=""
    case "$(systemd-detect-virt 2>/dev/null)" in
        oracle) packages+=(virtualbox-guest-utils); guest_services="vboxservice.service" ;;
        vmware) packages+=(open-vm-tools gtkmm3); guest_services="vmtoolsd.service" ;;
    esac
    local gpu nvidia=false
    while read -r gpu; do
        if [ "$gpu" = "#nvidia" ]; then nvidia=true; else packages+=("$gpu"); fi
    done < <(bash "$source_dir/linux/installer/gpu-packages.sh")

    step 10 "Downloading and installing Arch Linux and Graphite Desk (the long part)..."
    # pacstrap's own progress, as the bar between 10 and 75.
    local total=${#packages[@]}
    pacstrap -K "$target" "${packages[@]}" 2>&1 | tee -a "$log" | grep --line-buffered -E '^\(\s*[0-9]+/[0-9]+\) installing' | \
        while read -r line; do
            local done_count all
            done_count="$(sed -E 's/^\(\s*([0-9]+)\/([0-9]+)\).*/\1/' <<<"$line")"
            all="$(sed -E 's/^\(\s*([0-9]+)\/([0-9]+)\).*/\2/' <<<"$line")"
            step $(( 10 + 65 * done_count / all )) "Installing ($done_count of $all): ${line##* installing }"
        done
    [ -x "$target/usr/bin/Hyprland" ] || { echo "packages" > /tmp/graphite-failed; return; }

    step 76 "Setting up the system..."
    genfstab -U "$target" >> "$target/etc/fstab"
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$target/etc/pacman.conf"
    mkdir -p "$target/opt/graphite-desk"
    cp -a "$source_dir/." "$target/opt/graphite-desk/"

    local root_uuid
    root_uuid="$(blkid -s PARTUUID -o value "$(part 2)")"
    local microcode
    microcode="$(cpu_microcode)"
    local kernel_options="root=PARTUUID=$root_uuid rw quiet splash loglevel=3"
    $nvidia && kernel_options="$kernel_options nvidia_drm.modeset=1 nvidia_drm.fbdev=1"

    cat > "$target/root/configure.sh" <<CONFIGURE
set -e
ln -sf "/usr/share/zoneinfo/$TIME_ZONE" /etc/localtime
hwclock --systohc
sed -i "s/^#\\($locale UTF-8\\)/\\1/" /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf
echo "KEYMAP=${console[$KEYBOARD]:-us}" > /etc/vconsole.conf
echo "graphite-pc" > /etc/hostname

useradd -m -G wheel,video,input -c "$FULL_NAME" -s /bin/bash "$USER_NAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Start-up: systemd-boot, straight into Graphite Desk.
bootctl install --esp-path=/boot
cat > /boot/loader/loader.conf <<LOADER
default graphite.conf
timeout 0
editor no
LOADER
cat > /boot/loader/entries/graphite.conf <<ENTRY
title Graphite Desk
linux /vmlinuz-linux
${microcode:+initrd /$microcode.img}
initrd /initramfs-linux.img
options $kernel_options
ENTRY

# In VirtualBox: its guest control signs in through PAM as "vboxservice" (Arch ships no rules).
if [ -n "$guest_services" ] && [ "\${guest_services#vboxservice}" != "$guest_services" ]; then
    printf '#%%PAM-1.0\nauth include system-auth\naccount include system-auth\nsession include system-auth\n' > /etc/pam.d/vboxservice
fi

# Memory: compressed swap in RAM.
printf '[zram0]\nzram-size = min(ram / 2, 8192)\n' > /etc/systemd/zram-generator.conf

systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service fstrim.timer systemd-timesyncd.service $guest_services

# The login screen, and the person's desktop from the copy in /opt.
bash /opt/graphite-desk/linux/greetd/setup.sh /opt/graphite-desk/linux "$KEYBOARD"
home=/home/$USER_NAME
mkdir -p "\$home/.config/quickshell" "\$home/.config/hypr" "\$home/.config/graphite"
ln -sfn /opt/graphite-desk/linux/quickshell "\$home/.config/quickshell/graphite"
ln -sfn /opt/graphite-desk/linux/hypr/hyprland.lua "\$home/.config/hypr/hyprland.lua"
$($nvidia && echo 'echo nvidia > "$home/.config/graphite/gpu"')
chown -R "$USER_NAME:$USER_NAME" "\$home" /opt/graphite-desk
CONFIGURE
    if ! arch-chroot "$target" bash /root/configure.sh >>"$log" 2>&1; then echo "configure" > /tmp/graphite-failed; return; fi
    # The password, apart from the script (never written to the new system's files).
    printf '%s:%s\n' "$USER_NAME" "$PASSWORD" | arch-chroot "$target" chpasswd >>"$log" 2>&1 || { echo "password" > /tmp/graphite-failed; return; }
    rm -f "$target/root/configure.sh"

    if [ "$GAMING" = yes ]; then
        step 85 "Setting up for games (Steam, Minecraft)..."
        arch-chroot "$target" env GRAPHITE_USER="$USER_NAME" bash /opt/graphite-desk/linux/gaming.sh --from-installer >>"$log" 2>&1 || echo "gaming" > /tmp/graphite-gaming-failed
    fi

    step 97 "Finishing..."
    cp "$log" "$target/var/log/graphite-install.log"
    sync
    step 100 "Done."
    sleep 1
}

rm -f /tmp/graphite-failed /tmp/graphite-gaming-failed
: > "$log"
install_steps | dialog --backtitle "$backtitle" --title "Installing Graphite Desk" --gauge "Starting..." 10 72 0

if [ -f /tmp/graphite-failed ]; then
    case "$(cat /tmp/graphite-failed)" in
        packages) fail "Downloading the packages didn't finish. Is the internet still on?" ;;
        disk | format | mount) fail "The disk couldn't be prepared. The disk has been erased; nothing else was installed." ;;
        *) fail "Setting up the new system didn't finish." ;;
    esac
fi
gaming_note=""
[ -f /tmp/graphite-gaming-failed ] && gaming_note="\n\nThe games setup didn't finish; run it again from Settings, Set up gaming."
umount -R "$target" 2>/dev/null

if [ -z "${GRAPHITE_ANSWERS:-}" ]; then
    say "Graphite Desk is installed.$gaming_note\n\nPress Enter to restart. Once the screen goes dark, take out the USB stick; the computer starts your new desktop. Sign in with the password you chose." 13
    # Everything is written and unmounted: no need to wait for the USB stick's services to stop
    # (which hangs when the stick is pulled out early).
    reboot -f
fi
