#!/usr/bin/env bash
# Pointer and keys inside the VM's desktop, for checks from Windows (needs ydotoold running
# with its socket at /tmp/.ydotool_socket, and wtype). Source it, then:
#   at X Y          move the pointer there (screen pixels)
#   click [left|right|middle]
#   drag X1 Y1 X2 Y2 [hold-ms]   press at one place, move in steps, hold, let go at the other
#   keys TEXT       type text;  key NAME...  press keys (wtype -k), e.g. key Escape
#   shot NAME       screenshot to NAME.png next to this file
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)"
export WAYLAND_DISPLAY=wayland-1
export YDOTOOL_SOCKET=/tmp/.ydotool_socket

# Hyprland places the pointer (ydotool's absolute moves are ignored); ydotool presses buttons.
at() { hyprctl dispatch "hl.dsp.cursor.move({ x = $1, y = $2 })" >/dev/null; ydotool mousemove -x 0 -y 0 >/dev/null 2>&1; sleep 0.2; }
button_code() { case "${1:-left}" in left) echo 0x00 ;; right) echo 0x01 ;; middle) echo 0x02 ;; esac; }
hex() { printf '0x%02X' "$1"; }
click() { local code; code=$(button_code "$1"); ydotool click "$(hex $((code | 0xC0)))" >/dev/null; sleep 0.3; }
press() { local code; code=$(button_code "$1"); ydotool click "$(hex $((code | 0x40)))" >/dev/null; }
release() { local code; code=$(button_code "$1"); ydotool click "$(hex $((code | 0x80)))" >/dev/null; }
drag() {
    at "$1" "$2"; press left; sleep 0.15
    local steps=12 i
    for i in $(seq 1 $steps); do
        at $(( $1 + ($3 - $1) * i / steps )) $(( $2 + ($4 - $2) * i / steps ))
    done
    sleep "$(awk "BEGIN { print ${5:-200} / 1000 }")"
    release left; sleep 0.4
}
keys() { wtype "$1"; sleep 0.3; }
key() { local name; for name in "$@"; do wtype -k "$name"; done; sleep 0.3; }
shot() { grim "$here/$1.png"; }
