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
if lspci 2>/dev/null | grep -E 'VGA|3D|Display' | grep -qi nvidia && pacman -Qq nvidia-open nvidia-open-dkms nvidia nvidia-dkms 2>/dev/null | grep -q .; then
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

quiet="quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"
$nvidia && quiet="$quiet nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
for entry in /boot/loader/entries/*.conf; do
    [ -f "$entry" ] || continue
    options="$(sed -n 's/^options //p' "$entry")"
    # Keep where the system is (root=, rd.luks...), replace the rest.
    keep="$(tr ' ' '\n' <<<"$options" | grep -E '^(root=|rd\.luks|rw$|ro$|resume=)' | tr '\n' ' ')"
    sed -i "s|^options .*|options ${keep}${quiet}|" "$entry"
done

# ---------- the login screen after the splash ----------

mkdir -p /etc/systemd/system/greetd.service.d
cat > /etc/systemd/system/greetd.service.d/graphite.conf <<'UNIT'
# Graphite Desk (system/boot-setup.sh): the login screen takes over from the start-up splash.
[Unit]
After=plymouth-quit-wait.service systemd-user-sessions.service
UNIT

mkinitcpio -P

# Everything written out now: the start-up partition is FAT, which a sudden power-off right
# after (or a reset) can leave corrupt.
sync
