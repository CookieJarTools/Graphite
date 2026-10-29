#!/usr/bin/env bash
# The Graphite Desk installer: puts Arch Linux with Graphite Desk on this computer. The USB
# stick opens its graphical front end (quickshell/installer.qml), which asks everything in a
# few friendly screens and runs this with the answers; without a screen it asks in plain text
# screens itself (dialog): the network (Wi-Fi, when there is no cable), the disk to use (all of
# it: everything on it is erased, after typing ERASE), the person's name and password, the
# time zone and keyboard, and whether to set up gaming. Then it installs and restarts into
# Graphite's login screen.
#
# It runs from the Graphite Desk USB stick (build-iso.sh makes it); Graphite Desk's
# repository (with its git history) is on the stick in /usr/share/graphite-desk and goes to
# /opt/graphite-desk, owned by the person: they can change it, pull updates and push, and the
# login screen can still read it. The Wi-Fi joined on the stick is kept for the new system.
# The log is /tmp/graphite-install.log, copied into the new system.
#
#   GRAPHITE_ANSWERS=file graphite-install   answers instead of questions:
#       DISK, FULL_NAME, USER_NAME, PASSWORD, TIME_ZONE, KEYBOARD, GAMING (yes|no), and
#       optionally LOCALE (en_GB.UTF-8...), HOST_NAME, HINT, ENCRYPT (yes|no: the disk, with
#       the password), APPS (Flathub ids), PACKAGES (Arch packages, for the apps Arch has),
#       THEME (dark|light|auto), AUTO_UPDATES (yes|no), CLAUDE_CODE (yes|no), PIN (4 digits, for signing in quickly)
#   GRAPHITE_PROGRESS=lines                  progress as lines for the graphical front end
#       ("PROGRESS <percent> <text>", "STAGE <disk|system|account|security|games|apps|finish>",
#       "ERROR <text>", "DONE") instead of dialog's screens
set -uo pipefail

source_dir=/usr/share/graphite-desk
target=/mnt
log=/tmp/graphite-install.log
export DIALOGRC=/usr/share/graphite-desk/linux/installer/dialogrc
title="Graphite Desk"
backtitle="Graphite Desk installer"

lines=false
[ "${GRAPHITE_PROGRESS:-}" = lines ] && lines=true

ask() { dialog --backtitle "$backtitle" --title "$title" --stdout "$@"; }
say() { $lines || dialog --backtitle "$backtitle" --title "$title" --msgbox "$1" "${2:-9}" 64; }
fail() {
    if $lines; then
        echo "ERROR $1"
    else
        dialog --backtitle "$backtitle" --title "Something went wrong" --msgbox "$1\n\nDetails are in $log. Restart to try again. Nothing on the computer was changed unless it says so above." 13 70
    fi
    exit 1
}

if [ -n "${GRAPHITE_ANSWERS:-}" ]; then
    # shellcheck disable=SC1090
    source "$GRAPHITE_ANSWERS"
fi

# ---------- the computer ----------

if [ ! -d /sys/firmware/efi ]; then
    $lines && fail "The installer was started in BIOS mode. Restart and choose the USB stick's UEFI entry."
    say "The installer was started in BIOS mode.\n\nRestart, open the boot menu (often F12, F11 or Esc), and choose the USB stick's UEFI entry." 11
    exit 1
fi

# ---------- the network ----------

online() { curl -s --max-time 5 -o /dev/null https://archlinux.org; }

# Wi-Fi through NetworkManager, as the new system has it: the network joined here is copied
# into the new system, so it's online at its first start.
connect_wifi() {
    local networks ssid password
    if ! nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
        say "No internet connection or Wi-Fi was found.\n\nPlug in a network cable, then press Enter." 10
        return
    fi
    nmcli device wifi rescan >/dev/null 2>&1
    sleep 4
    mapfile -t networks < <(nmcli -t -f SSID device wifi list 2>/dev/null | sed 's/\\:/:/g' | grep -v '^$' | sort -u)
    if [ ${#networks[@]} -eq 0 ]; then
        say "No Wi-Fi networks were found nearby.\n\nPlug in a network cable, or move closer to the router, then press Enter." 10
        return
    fi
    local items=()
    for ssid in "${networks[@]}"; do items+=("$ssid" ""); done
    ssid="$(ask --menu "Choose your Wi-Fi network:" 18 64 10 "${items[@]}")" || return
    password="$(ask --insecure --passwordbox "Password for \"$ssid\". Leave empty if there isn't one:" 9 64)" || return
    if [ -n "$password" ]; then
        nmcli device wifi connect "$ssid" password "$password" >>"$log" 2>&1
    else
        nmcli device wifi connect "$ssid" >>"$log" 2>&1
    fi
    sleep 4
}

until online; do
    $lines && fail "No internet connection. Connect to a network first."
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
    ask --defaultno --yesno "Everything on this disk will be erased:\n\n    $DISK  ($disk_note)\n\nThis includes Windows and all your files. It can't be undone.\n\nErase it and install Graphite Desk?" 14 64 || exit 1
    confirm="$(ask --inputbox "To confirm, type ERASE in capitals:" 9 64)" || exit 1
    [ "$confirm" = "ERASE" ] || { say "Nothing was erased. Restart to start again."; exit 1; }
fi

# ---------- the person ----------

if [ -z "${FULL_NAME:-}" ]; then
    FULL_NAME="$(ask --inputbox "What's your name?" 9 64)" || exit 1
    suggested="$(echo "${FULL_NAME%% *}" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')"
    while true; do
        USER_NAME="$(ask --inputbox "User name, in lower-case letters and numbers:" 9 64 "${suggested:-me}")" || exit 1
        [[ "$USER_NAME" =~ ^[a-z][a-z0-9_-]{0,30}$ ]] && break
        say "Use lower-case letters and numbers, starting with a letter."
    done
    while true; do
        PASSWORD="$(ask --insecure --passwordbox "Choose a password:" 9 64)" || exit 1
        again="$(ask --insecure --passwordbox "Type it again:" 9 64)" || exit 1
        if [ -z "$PASSWORD" ]; then say "The password can't be empty."; continue; fi
        [ "$PASSWORD" = "$again" ] && break
        say "The passwords don't match. Try again."
    done
fi

if [ -z "${TIME_ZONE:-}" ]; then
    guess="$(curl -s --max-time 5 https://ipapi.co/timezone 2>/dev/null)"
    [ -f "/usr/share/zoneinfo/$guess" ] || guess="Europe/London"
    if ask --yesno "Is this your time zone?\n\n    $guess" 10 64; then
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
locale="${LOCALE:-en_US.UTF-8}"
[ -z "${LOCALE:-}" ] && case "$KEYBOARD" in gb | ie) locale="en_GB.UTF-8" ;; esac
grep -q "^#\?$locale UTF-8" /etc/locale.gen 2>/dev/null || locale="en_US.UTF-8"

# The graphical front end's choices (the text screens don't ask these).
ENCRYPT="${ENCRYPT:-no}"
APPS="${APPS:-}"
PACKAGES="${PACKAGES:-}"
THEME="${THEME:-dark}"
AUTO_UPDATES="${AUTO_UPDATES:-no}"
HINT="${HINT:-}"
HOST_NAME="${HOST_NAME:-graphite-pc}"
[[ "$HOST_NAME" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || HOST_NAME=graphite-pc

if [ -z "${GAMING:-}" ]; then
    if ask --yesno "Set up for games?\n\nInstalls Steam, Minecraft, GameMode and an FPS counter. You can also do this later from the Control Panel." 11 64; then
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

# The steps, each moving the bar; the output goes to the log. For the graphical front end each
# also says which stage it is in (STAGE), and the bar's place (PROGRESS).
step() {
    if $lines; then echo "PROGRESS $1 $2"; else printf 'XXX\n%s\n%s\nXXX\n' "$1" "$2"; fi
}
stage() { $lines && echo "STAGE $1"; return 0; }

install_steps() {
    stage disk
    step 2 "Preparing the disk..."
    umount -R "$target" >>"$log" 2>&1
    cryptsetup close cryptroot >>"$log" 2>&1
    wipefs -af "$DISK" >>"$log" 2>&1
    sgdisk --zap-all "$DISK" >>"$log" 2>&1
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot -n 2:0:0 -t 2:8300 -c 2:graphite "$DISK" >>"$log" 2>&1 || { echo "disk" > /tmp/graphite-failed; return; }
    partprobe "$DISK" >>"$log" 2>&1; sleep 2
    mkfs.fat -F 32 -n BOOT "$(part 1)" >>"$log" 2>&1
    # Encrypted: the whole system behind the person's password, asked when the computer starts.
    local root_device
    root_device="$(part 2)"
    if [ "$ENCRYPT" = yes ]; then
        step 4 "Encrypting the disk..."
        printf '%s' "$PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$(part 2)" >>"$log" 2>&1 || { echo "encrypt" > /tmp/graphite-failed; return; }
        printf '%s' "$PASSWORD" | cryptsetup open --key-file=- "$(part 2)" cryptroot >>"$log" 2>&1 || { echo "encrypt" > /tmp/graphite-failed; return; }
        root_device=/dev/mapper/cryptroot
    fi
    mkfs.ext4 -F -L graphite "$root_device" >>"$log" 2>&1 || { echo "format" > /tmp/graphite-failed; return; }
    mount "$root_device" "$target" && mount --mkdir "$(part 1)" "$target/boot" || { echo "mount" > /tmp/graphite-failed; return; }

    stage system
    step 6 "Turning on 32-bit packages and the fastest mirrors..."
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    pacman -Sy --noconfirm >>"$log" 2>&1

    local packages=(
        base linux linux-firmware linux-headers sudo nano man-db $(cpu_microcode)
        networkmanager network-manager-applet networkmanager-openvpn bluez bluez-utils
        pipewire wireplumber pipewire-pulse pipewire-alsa
        hyprland quickshell qt6-wayland qt6-svg xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
        hypridle hyprsunset brightnessctl
        greetd papirus-icon-theme adwaita-icon-theme capitaine-cursors inter-font ttf-jetbrains-mono noto-fonts noto-fonts-emoji dconf
        kitty nautilus firefox libnotify grim
        loupe celluloid papers slurp wl-clipboard xdg-user-dirs udisks2 gvfs exfatprogs ntfs-3g dosfstools
        distrobox podman flatpak fuse2 gnome-software xdg-utils desktop-file-utils
        power-profiles-daemon zram-generator pciutils git pacman-contrib ufw plymouth
        cups cups-pk-helper system-config-printer avahi nss-mdns
        ocean-sound-theme libldm gptfdisk ntfsprogs nautilus-python gcc make pkgconf
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

    step 10 "Downloading and installing Arch Linux and Graphite Desk..."
    # pacstrap's own progress, as the bar between 10 and 75.
    pacstrap -K "$target" "${packages[@]}" 2>&1 | tee -a "$log" | grep --line-buffered -E '^\(\s*[0-9]+/[0-9]+\) installing' | \
        while read -r line; do
            local done_count all
            done_count="$(sed -E 's/^\(\s*([0-9]+)\/([0-9]+)\).*/\1/' <<<"$line")"
            all="$(sed -E 's/^\(\s*([0-9]+)\/([0-9]+)\).*/\2/' <<<"$line")"
            step $(( 10 + 65 * done_count / all )) "Installing ($done_count of $all): ${line##* installing }"
        done
    [ -x "$target/usr/bin/Hyprland" ] || { echo "packages" > /tmp/graphite-failed; return; }

    stage account
    step 76 "Setting up the system and your account..."
    genfstab -U "$target" >> "$target/etc/fstab"
    sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$target/etc/pacman.conf"
    mkdir -p "$target/opt/graphite-desk"
    cp -a "$source_dir/." "$target/opt/graphite-desk/"

    local microcode
    microcode="$(cpu_microcode)"
    local kernel_options
    if [ "$ENCRYPT" = yes ]; then
        kernel_options="rd.luks.name=$(blkid -s UUID -o value "$(part 2)")=cryptroot root=/dev/mapper/cryptroot rw quiet splash loglevel=3"
    else
        kernel_options="root=PARTUUID=$(blkid -s PARTUUID -o value "$(part 2)") rw quiet splash loglevel=3"
    fi
    $nvidia && kernel_options="$kernel_options nvidia_drm.modeset=1 nvidia_drm.fbdev=1"

    # The Wi-Fi joined on the stick, for the new system (root's own, readable by root only).
    local connection
    for connection in /etc/NetworkManager/system-connections/*.nmconnection; do
        [ -f "$connection" ] || continue
        install -d -m 700 "$target/etc/NetworkManager/system-connections"
        sed -e '/^interface-name=/d' -e '/^permissions=/d' -e '/^mac-address=/d' "$connection" > "$target/etc/NetworkManager/system-connections/$(basename "$connection")"
        chmod 600 "$target/etc/NetworkManager/system-connections/$(basename "$connection")"
    done

    local dark=true theme_mode="" auto_updates=false auto_word=off
    [ "$THEME" = light ] && dark=false
    [ "$THEME" = auto ] && theme_mode=auto
    [ "$AUTO_UPDATES" = yes ] && auto_updates=true && auto_word=on

    cat > "$target/root/configure.sh" <<CONFIGURE
set -e
ln -sf "/usr/share/zoneinfo/$TIME_ZONE" /etc/localtime
hwclock --systohc
sed -i "s/^#\\($locale UTF-8\\)/\\1/" /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf
echo "KEYMAP=${console[$KEYBOARD]:-us}" > /etc/vconsole.conf
echo "$HOST_NAME" > /etc/hostname

useradd -m -G wheel,video,input -c "$FULL_NAME" -s /bin/bash "$USER_NAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Start-up: systemd-boot, straight into Graphite Desk (boot-setup.sh below makes it quiet).
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

# Printers on the network are found by name.
sed -i 's/^hosts: mymachines /hosts: mymachines mdns_minimal [NOTFOUND=return] /' /etc/nsswitch.conf

systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service fstrim.timer systemd-timesyncd.service cups.socket avahi-daemon.service $guest_services

# The login screen, and the person's desktop from the copy in /opt.
bash /opt/graphite-desk/linux/greetd/setup.sh /opt/graphite-desk/linux "$KEYBOARD"
# A quiet start: the splash, NVIDIA's driver first, the login screen after (and the initramfs).
bash /opt/graphite-desk/linux/system/boot-setup.sh
home=/home/$USER_NAME
mkdir -p "\$home/.config/quickshell" "\$home/.config/hypr" "\$home/.config/graphite"
ln -sfn /opt/graphite-desk/linux/quickshell "\$home/.config/quickshell/graphite"
ln -sfn /opt/graphite-desk/linux/hypr/hyprland.lua "\$home/.config/hypr/hyprland.lua"
$($nvidia && echo 'echo nvidia > "$home/.config/graphite/gpu"')
# What was chosen in the installer, for the desktop's first start.
echo '{"dark": $dark, "themeMode": "$theme_mode", "autoUpdates": $auto_updates}' > "\$home/.config/graphite/first-run.json"
printf $auto_word > "\$home/.config/graphite/auto-updates"
chown -R "$USER_NAME:$USER_NAME" "\$home" /opt/graphite-desk
CONFIGURE
    if ! arch-chroot "$target" bash /root/configure.sh >>"$log" 2>&1; then echo "configure" > /tmp/graphite-failed; return; fi
    # The password and its hint, apart from the script (never written to the new system's files).
    printf '%s:%s\n' "$USER_NAME" "$PASSWORD" | arch-chroot "$target" chpasswd >>"$log" 2>&1 || { echo "password" > /tmp/graphite-failed; return; }
    if [ -n "$HINT" ]; then
        install -d -m 755 "$target/var/lib/graphite" "$target/var/lib/graphite/hints"
        printf '%s\n' "${HINT:0:80}" > "$target/var/lib/graphite/hints/$USER_NAME"
        chmod 644 "$target/var/lib/graphite/hints/$USER_NAME"
    fi
    rm -f "$target/root/configure.sh"

    stage security
    step 84 "Setting up the firewall and updates..."
    arch-chroot "$target" bash /opt/graphite-desk/linux/system/install.sh >>"$log" 2>&1 || echo "The security setup didn't finish." >>"$log"
    # The sign-in PIN, when one was chosen (kept only as a salted hash).
    if [[ "${PIN:-}" =~ ^[0-9]{4,8}$ ]]; then
        echo "$PIN" | arch-chroot "$target" /usr/local/lib/graphite/graphite-admin pin "$USER_NAME" >>"$log" 2>&1 || echo "The PIN wasn't set." >>"$log"
    fi

    if [ "$GAMING" = yes ]; then
        stage games
        step 85 "Installing Steam and Minecraft..."
        arch-chroot "$target" env GRAPHITE_USER="$USER_NAME" bash /opt/graphite-desk/linux/gaming.sh --from-installer >>"$log" 2>&1 || echo "gaming" > /tmp/graphite-gaming-failed
    fi

    # The apps picked in the installer: Arch Linux's own where it has them, Flathub for the rest
    # (for everyone on the computer).
    local apps=() packages=() app count=0
    for app in $APPS; do [[ "$app" =~ ^[A-Za-z0-9._-]+$ ]] && apps+=("$app"); done
    for app in $PACKAGES; do [[ "$app" =~ ^[a-z0-9@._+-]+$ ]] && packages+=("$app"); done
    if [ ${#packages[@]} -gt 0 ]; then
        stage apps
        step 87 "Installing your apps..."
        # All at once; when one can't be had, the rest still go in, one by one.
        if ! arch-chroot "$target" pacman -S --needed --noconfirm "${packages[@]}" >>"$log" 2>&1; then
            for app in "${packages[@]}"; do
                arch-chroot "$target" pacman -S --needed --noconfirm "$app" >>"$log" 2>&1 || echo "$app" >> /tmp/graphite-apps-failed
            done
        fi
    fi
    if [ ${#apps[@]} -gt 0 ]; then
        stage apps
        arch-chroot "$target" flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$log" 2>&1
        for app in "${apps[@]}"; do
            count=$(( count + 1 ))
            step $(( 88 + 8 * (count - 1) / ${#apps[@]} )) "Installing your apps ($count of ${#apps[@]})..."
            arch-chroot "$target" flatpak install --system -y --noninteractive flathub "$app" >>"$log" 2>&1 || echo "$app" >> /tmp/graphite-apps-failed
        done
    fi

    # Claude Code: Anthropic's own installer, for the person (it lands in ~/.local/bin).
    if [ "${CLAUDE_CODE:-no}" = yes ]; then
        stage apps
        step 96 "Installing Claude Code..."
        arch-chroot "$target" runuser -l "$USER_NAME" -c 'curl -fsSL https://claude.ai/install.sh | bash' >>"$log" 2>&1 || echo "claude-code" >> /tmp/graphite-apps-failed
    fi

    stage finish
    step 97 "Finishing..."
    # Everything in their home folder theirs (some steps above run as the system).
    arch-chroot "$target" chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME" >>"$log" 2>&1
    cp "$log" "$target/var/log/graphite-install.log"
    # Why the installer's screens didn't open, when the text ones were used instead.
    [ -f /tmp/graphite-gui.log ] && cp /tmp/graphite-gui.log "$target/var/log/graphite-install-screens.log"
    sync
    step 100 "Done."
    sleep 1
}

rm -f /tmp/graphite-failed /tmp/graphite-gaming-failed /tmp/graphite-apps-failed
: > "$log"
if $lines; then
    install_steps
else
    install_steps | dialog --backtitle "$backtitle" --title "Installing Graphite Desk" --gauge "Starting..." 10 72 0
fi

if [ -f /tmp/graphite-failed ]; then
    case "$(cat /tmp/graphite-failed)" in
        packages) fail "The download didn't finish. Check your internet connection." ;;
        disk | format | mount | encrypt) fail "The disk couldn't be prepared. It has been erased, but nothing was installed." ;;
        *) fail "Setting up the new system didn't finish." ;;
    esac
fi
gaming_note=""
[ -f /tmp/graphite-gaming-failed ] && gaming_note="\n\nGaming setup didn't finish. Try again from Apps in the Control Panel."
umount -R "$target" 2>/dev/null
cryptsetup close cryptroot 2>/dev/null

if $lines; then
    [ -f /tmp/graphite-gaming-failed ] && echo "NOTE games"
    [ -f /tmp/graphite-apps-failed ] && echo "NOTE apps $(tr '\n' ' ' < /tmp/graphite-apps-failed)"
    echo "DONE"
elif [ -z "${GRAPHITE_ANSWERS:-}" ]; then
    say "Graphite Desk is installed.$gaming_note\n\nPress Enter to restart. When the screen goes dark, remove the USB stick. Then sign in with the password you chose." 13
    # Everything is written and unmounted: no need to wait for the USB stick's services to stop
    # (which hangs when the stick is pulled out early).
    reboot -f
fi
