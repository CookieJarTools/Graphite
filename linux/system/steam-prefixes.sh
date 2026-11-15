#!/usr/bin/env bash
# Steam games on exFAT and FAT drives work as they do anywhere else. Proton builds each game's
# Windows set-up (its prefix, in the library's steamapps/compatdata) from links, which those
# drives can't hold, so the game stops before it starts. Instead, a folder on the system drive
# (~/.local/share/proton-prefixes) takes the place of each such library's compatdata, put there
# by graphite-admin steam-prefixes (no password needed for that: 50-graphite.rules).
# The shell runs this when a drive connects and whenever Steam's libraries or games change
# (services/Drives.qml). It runs `release` before disconnecting a drive, which the folder
# would otherwise keep in use.
#
#   steam-prefixes.sh                     every library that needs it
#   steam-prefixes.sh release PARTITION   one partition's let go, before it's disconnected
set -uo pipefail
admin=/usr/local/lib/graphite/graphite-admin

# Only once the system parts that do this are in place (Control Panel > Updates). The rule
# that lets it run without a password (50-graphite.rules) is installed in the same step, so a
# password is never asked from here.
grep -q steam-prefixes "$admin" 2>/dev/null || exit 0

# The folder in place in a library on this mount point.
held() {
    local target
    while IFS= read -r target; do
        case "$target" in
            "$1"/steamapps/compatdata | "$1"/*/steamapps/compatdata) return 0 ;;
        esac
    done < <(findmnt -lno TARGET)
    return 1
}

if [ "${1:-}" = release ]; then
    part="${2:-}"
    [ -b "$part" ] || exit 0
    while IFS= read -r device; do
        while IFS= read -r mount; do
            if [ -n "$mount" ] && held "$mount"; then
                pkexec "$admin" steam-prefixes-release "$part"
                exit 0
            fi
        done < <(findmnt -lno TARGET -S "$device" 2>/dev/null)
    done < <(lsblk -lnpo NAME "$part" 2>/dev/null)
    exit 0
fi

libraries="$HOME/.local/share/Steam/steamapps/libraryfolders.vdf"
[ -f "$libraries" ] || exit 0
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/graphite-steam-prefixes.lock"
flock 9
while IFS= read -r library; do
    [ -d "$library/steamapps" ] || continue
    case "$(findmnt -no FSTYPE -T "$library/steamapps" 2>/dev/null)" in
        exfat | vfat | msdos) ;;
        *) continue ;;
    esac
    # In place already, and kept out of Files' drives.
    mountpoint -q "$library/steamapps/compatdata" &&
        findmnt --mtab -no OPTIONS -M "$library/steamapps/compatdata" | grep -q x-gvfs-hide && continue
    # The drive's own files belong to whoever connected it; anything else (/boot) is left be.
    [ -O "$library/steamapps" ] || continue
    pkexec "$admin" steam-prefixes
    exit 0
done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$libraries")
exit 0
