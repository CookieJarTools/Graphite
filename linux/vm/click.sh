# click.sh X Y: moves the pointer there (Hyprland) and clicks (ydotool), for test runs.
hyprctl dispatch "hl.dsp.cursor.move({ x = $1, y = $2 })" >/dev/null
sleep 0.2
YDOTOOL_SOCKET=/tmp/.ydotool_socket ydotool click 0xC0 >/dev/null
