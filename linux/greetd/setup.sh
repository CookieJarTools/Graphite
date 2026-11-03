#!/usr/bin/env bash
# Makes Graphite's login screen the way into the computer: greetd starts a small Hyprland
# (hypr/greeter.lua) running the greeter (quickshell/greeter.qml) as the "greeter" user, on the
# first console, instead of a text login. Run as root with where Graphite lives (its linux
# folder) and the keyboard layout:   setup.sh /opt/graphite-desk gb
# The installer runs it; the test VM's install too.
set -euo pipefail
graphite="${1:?where Graphite lives}"
layout="${2:-gb}"

mkdir -p /etc/greetd /etc/graphite
echo "$layout" > /etc/graphite/keyboard

cat > /etc/greetd/config.toml <<CONFIG
# Graphite's login screen (linux/greetd/setup.sh).
[terminal]
vt = 1

[default_session]
command = "sh -c 'exec start-hyprland -- --config $graphite/hypr/greeter.lua > /dev/null 2>&1'"
user = "greeter"
CONFIG

# The greeter reads Graphite's files; in the test VM they are on the shared folder.
if getent group vboxsf >/dev/null; then usermod -aG vboxsf greeter; fi
usermod -aG video,input greeter 2>/dev/null || true

# No more signing in on the console by itself: the login screen asks.
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
systemctl disable getty@tty1.service 2>/dev/null || true
systemctl enable greetd.service
