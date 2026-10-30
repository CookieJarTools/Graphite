#!/usr/bin/env bash
# Starting up the way Windows does (run as root; the installer runs it, and install.sh for a
# machine installed before it existed):
#   - quiet: a splash with the computer maker's logo and a spinner (Plymouth's "bgrt" theme)
#     from the moment the kernel starts until the login screen, with no text or cursor, and the
#     disk's password (when encrypted) asked on it;
#   - NVIDIA: its driver loaded first, in the initramfs, and nouveau (the open-source driver,
#     which can't drive recent cards well and takes seconds loading firmware) kept out;
#   - the login screen waits for the splash to finish, so nothing flashes between them.
# Then it rebuilds the initramfs. Safe to run again.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }

nvidia=false
# Its driver, from the whole package list (pacman -Qq with names fails when one isn't installed).
if lspci 2>/dev/null | grep -E 'VGA|3D|Display' | grep -i nvidia >/dev/null &&
    grep -qxE 'nvidia(-open)?(-dkms)?' <<<"$(pacman -Qq 2>/dev/null)"; then
    nvidia=true
fi
encrypted=false
if findmnt -no SOURCE / | grep -q '^/dev/mapper/' || grep -qs 'rd.luks' /boot/loader/entries/*.conf; then
    encrypted=true
fi
splash=false
pacman -Qq plymouth >/dev/null 2>&1 && splash=true

# ---------- the initramfs ----------

hooks="base systemd"
$splash && hooks="$hooks plymouth"
hooks="$hooks autodetect microcode modconf"
$nvidia || hooks="$hooks kms" # kms would bring nouveau in ahead of NVIDIA's own driver
hooks="$hooks keyboard sd-vconsole block"
$encrypted && hooks="$hooks sd-encrypt"
hooks="$hooks filesystems fsck"
sed -i "s/^HOOKS=.*/HOOKS=($hooks)/" /etc/mkinitcpio.conf
if $nvidia; then
    sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    printf 'options nvidia_drm modeset=1 fbdev=1\n' > /etc/modprobe.d/graphite-nvidia.conf
fi

# ---------- the splash ----------

if $splash; then
    mkdir -p /etc/plymouth
    printf '[Daemon]\nTheme=bgrt\nShowDelay=0\nDeviceTimeout=8\n' > /etc/plymouth/plymouthd.conf
fi

# ---------- the kernel's options ----------

# loglevel=0: nothing from the kernel over the logo, not even its emergency notices, which some
# firmware sets off at every start (AMD X570 boards: "No irq handler for 1.55", a line for each
# processor core, on screen for seconds until the splash). That would hide a crash at start-up
# too, so the boot menu (hold Space as the computer starts) has "Graphite Desk (start-up
# messages)", the same start with everything shown.
quiet="quiet splash loglevel=0 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"
graphics=""
$nvidia && graphics=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
# Where the system is (root=, rd.luks...), from an entry's options.
where() { sed -n 's/^options //p' "$1" | tr ' ' '\n' | grep -E '^(root=|rd\.luks|rw$|ro$|resume=)' | tr '\n' ' '; }
for entry in /boot/loader/entries/*.conf; do
    [ -f "$entry" ] && [ "${entry##*/}" != graphite-messages.conf ] || continue
    sed -i "s|^options .*|options $(where "$entry")${quiet}${graphics}|" "$entry"
done
main=/boot/loader/entries/graphite.conf
if [ -f "$main" ]; then
    sed -e 's/^title .*/title Graphite Desk (start-up messages)/' \
        -e "s|^options .*|options $(where "$main")${graphics# }|" "$main" > /boot/loader/entries/graphite-messages.conf
fi

# ---------- the login screen after the splash ----------

mkdir -p /etc/systemd/system/greetd.service.d
cat > /etc/systemd/system/greetd.service.d/graphite.conf <<'UNIT'
# Graphite Desk (system/boot-setup.sh): the login screen takes over from the start-up splash.
[Unit]
After=plymouth-quit-wait.service systemd-user-sessions.service
UNIT

mkinitcpio -P

# Done for this copy of the script (install.sh runs it again when it changes).
mkdir -p /var/lib/graphite
sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1 > /var/lib/graphite/boot-setup

# Everything written out now: the start-up partition is FAT, which a sudden power-off right
# after (or a reset) can leave corrupt.
sync
