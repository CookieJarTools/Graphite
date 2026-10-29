#!/usr/bin/env bash
# The Control Panel's Troubleshoot: checks what most often stops apps opening, one line each:
#   CHECK <id> <ok|warn|fail> <title>|<what was found>|<fix id, if there is one>
# and then the apps that didn't open lately:
#   FAILED <time>|<app>|<its last words>
# Runs as the person; nothing here changes anything.
check() { printf 'CHECK %s %s %s|%s|%s\n' "$1" "$2" "$3" "$4" "${5:-}"; }

# ---------- graphics ----------

gpu="$(lspci -k 2>/dev/null | grep -A3 -E 'VGA|3D controller' )"
if grep -qi nvidia <<<"$gpu"; then
    driver="$(grep -i nvidia -A3 <<<"$gpu" | sed -n 's/.*Kernel driver in use: //p' | head -1)"
    if [ "$driver" = nvidia ] && [ -e /sys/module/nvidia_drm ]; then
        check graphics ok "Graphics" "The NVIDIA driver is working. Version $(cat /sys/module/nvidia/version 2>/dev/null)."
    else
        why="$(journalctl -k -b --no-pager -q 2>/dev/null | grep -iE 'nvidia.*(error|fail)|NVRM' | tail -1 | cut -c1-160)"
        check graphics fail "Graphics" "The NVIDIA driver isn't working. The card is using ${driver:-no driver}. ${why}" drivers
    fi
else
    check graphics ok "Graphics" "$(grep -E 'VGA|3D' <<<"$gpu" | head -1 | sed 's/^[^:]*: //' | cut -c1-80)"
fi

# ---------- your home folder ----------

foreign="$(find "$HOME" -xdev -maxdepth 4 ! -user "$(id -u)" -print -quit 2>/dev/null)"
if [ -n "$foreign" ]; then
    check home fail "Your files" "Apps can't save to some of your folders, such as ${foreign/#$HOME/~}." home
else
    check home ok "Your files" "Apps can save to your folders."
fi
free="$(df -P "$HOME" | awk 'NR==2 {print int($4/1048576)}')"
if [ "${free:-0}" -lt 2 ]; then
    check space fail "Space" "Only ${free} GB free. Some apps won't start without more space." clean
else
    check space ok "Space" "${free} GB free."
fi

# ---------- Firefox ----------

for profiles in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
    [ -e "$profiles" ] || continue
    if [ ! -w "$profiles" ] || find "$profiles" -maxdepth 2 ! -user "$(id -u)" -print -quit 2>/dev/null | grep -q .; then
        check firefox fail "Firefox" "Firefox can't save its settings." home
    elif [ -f "$profiles/profiles.ini" ] && ! grep -q '^Path=' "$profiles/profiles.ini"; then
        check firefox fail "Firefox" "Firefox's profile list is damaged." firefox
    else
        while IFS= read -r path; do
            case "$path" in /*) full="$path" ;; *) full="$profiles/$path" ;; esac
            [ -d "$full" ] || { check firefox fail "Firefox" "Firefox's profile folder is missing." firefox; break; }
        done < <(sed -n 's/^Path=//p' "$profiles/profiles.ini" 2>/dev/null)
    fi
done

# ---------- apps from Flathub on NVIDIA ----------

if [ -e /sys/module/nvidia ] && command -v flatpak >/dev/null && flatpak list --app --columns=application 2>/dev/null | grep -q .; then
    want="GL.nvidia-$(tr . - < /sys/module/nvidia/version)"
    if flatpak list --runtime --columns=application 2>/dev/null | grep -q "$want"; then
        check flatpak ok "Flathub apps" "They have what they need for the NVIDIA driver."
    else
        check flatpak fail "Flathub apps" "They're missing a part for the NVIDIA driver, so they can't open." flatpak
    fi
fi

# ---------- the desktop's helpers ----------

missing=""
for unit in xdg-desktop-portal xdg-desktop-portal-hyprland; do
    systemctl --user is-active --quiet "$unit" || missing="$missing $unit"
done
if [ -n "$missing" ]; then
    check portals fail "Background services" "Some background services apps need aren't running:$missing." portals
else
    check portals ok "Background services" "Running."
fi

if curl -s --max-time 5 -o /dev/null https://archlinux.org; then
    check internet ok "Internet" "Connected."
else
    check internet warn "Internet" "Not connected. You need it for updates and Flathub apps."
fi

# ---------- apps that didn't open ----------

failures="${XDG_CACHE_HOME:-$HOME/.cache}/graphite/apps/failures"
[ -f "$failures" ] && tail -8 "$failures" | tac | while IFS=$'\t' read -r time app words; do
    printf 'FAILED %s|%s|%s\n' "$time" "$app" "$words"
done
exit 0
