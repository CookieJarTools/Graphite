#!/usr/bin/env bash
# Puts Graphite's system parts in place (as root): the Control Panel's administrator
# helper and the system update, root-owned in /usr/local/lib/graphite (so the copy in
# /opt/graphite-desk, which its owner can edit, never runs as root by itself), their systemd
# units (and the one opening Windows dynamic disks), the polkit rules, the hard drives'
# scheduler, the folder for password hints, the compressed swap, and the firewall, on.
# The installer runs it; afterwards the Control Panel's Updates page offers it when these
# files change (graphite-admin install).
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }

install -d -m 755 /usr/local/lib/graphite /var/lib/graphite /var/lib/graphite/hints
install -m 755 -o root -g root "$here/graphite-admin" "$here/system-update" "$here/pin-check" /usr/local/lib/graphite/

# Signing in with a PIN: checked in front of the password, on the login screen (greetd) and
# the lock screen (its own PAM service, graphite-lock).
pin_line="auth sufficient pam_exec.so quiet expose_authtok /usr/local/lib/graphite/pin-check"
cat > /etc/pam.d/graphite-lock <<PAM
#%PAM-1.0
# Graphite's lock screen: a PIN, or the password (system/install.sh).
$pin_line
auth include login
account include login
PAM
if [ -f /etc/pam.d/greetd ] && ! grep -q pin-check /etc/pam.d/greetd; then
    sed -i "0,/^auth/s|^auth|$pin_line\n&|" /etc/pam.d/greetd
fi
# And when an administrator is asked for (installing apps, changing settings), as on Windows.
# Newer polkit keeps its file in /usr/lib/pam.d; a copy in /etc takes its place.
if [ ! -f /etc/pam.d/polkit-1 ] && [ -f /usr/lib/pam.d/polkit-1 ]; then
    cp /usr/lib/pam.d/polkit-1 /etc/pam.d/polkit-1
fi
if [ -f /etc/pam.d/polkit-1 ] && ! grep -q pin-check /etc/pam.d/polkit-1; then
    sed -i "0,/^auth/s|^auth|$pin_line\n&|" /etc/pam.d/polkit-1
fi
# Wrong passwords: the account rests for 2 minutes after 10 (as on Windows), not Arch's own
# 10 minutes after 3, which would refuse the right password after the screens' short pause.
if [ -f /etc/security/faillock.conf ]; then
    sed -i -e 's/^#\? *deny *=.*/deny = 10/' -e 's/^#\? *unlock_time *=.*/unlock_time = 120/' /etc/security/faillock.conf
fi
install -m 644 "$here/graphite-update.service" "$here/graphite-update-auto.service" "$here/graphite-update-auto.timer" "$here/graphite-dynamic-disks.service" /etc/systemd/system/
install -m 644 "$here/org.graphite.admin.policy" /usr/share/polkit-1/actions/
install -d -m 750 /etc/polkit-1/rules.d
install -m 644 "$here/50-graphite.rules" /etc/polkit-1/rules.d/
install -m 644 "$here/60-graphite-disks.rules" /etc/udev/rules.d/
udevadm control --reload 2>/dev/null && udevadm trigger --subsystem-match=block --action=change 2>/dev/null || true
# Memory: compressed swap in RAM, its size used from the next start, and swap tuned for it, at once.
install -m 644 "$here/zram-generator.conf" /etc/systemd/zram-generator.conf
install -m 644 "$here/99-graphite-memory.conf" /etc/sysctl.d/
sysctl -q -p /etc/sysctl.d/99-graphite-memory.conf 2>/dev/null || true
# What was installed, so the Updates page can tell when the repository's copy has moved on.
cat "$here"/graphite-admin "$here"/system-update "$here"/pin-check "$here"/boot-setup.sh "$here"/*.service "$here"/*.timer "$here"/*.policy "$here"/*.rules "$here"/*.conf | sha256sum | cut -d' ' -f1 > /var/lib/graphite/system-parts
chmod 644 /var/lib/graphite/system-parts

# A quiet start (boot-setup.sh): on machines installed before it existed, with the splash's
# package fetched first, and again whenever it has changed. The installer runs it itself.
if [ -d /boot/loader/entries ] && [ "$(sha256sum "$here/boot-setup.sh" | cut -d' ' -f1)" != "$(cat /var/lib/graphite/boot-setup 2>/dev/null)" ]; then
    pacman -Qq plymouth >/dev/null 2>&1 || pacman -S --needed --noconfirm plymouth >/dev/null 2>&1 || true
    bash "$here/boot-setup.sh" || echo "The quiet start-up couldn't be set up."
fi

systemctl daemon-reload 2>/dev/null || true
systemctl enable graphite-update-auto.timer 2>/dev/null || true

if command -v ufw >/dev/null; then
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
    # From the installer (a chroot, where ufw can't load its rules), on from the first start.
    sed -i 's/^ENABLED=no/ENABLED=yes/' /etc/ufw/ufw.conf
    systemctl enable ufw.service 2>/dev/null || true
fi
