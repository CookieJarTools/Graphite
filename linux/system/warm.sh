#!/usr/bin/env bash
# Apps open quickly from a hard drive. The first time an app opens after the computer starts,
# everything it needs is read from the disk, and on a spinning drive that takes many seconds
# (Zen: about twenty), where a second open, from memory, takes a fraction of one. So once an
# app is up, launch.sh has the files it holds noted here (learn), and a little after signing in
# the shell has the files of the apps used most read into memory (warm), with only the disk's
# spare time, so they open as fast as the second time. Solid-state drives don't need it: warm
# does nothing there.
#
#   warm.sh learn ID UNIT   from launch.sh, in the background (UNIT: the app's scope)
#   warm.sh warm ID...      from the shell (services/Apps.qml), most used first
#
# The lists are ~/.cache/graphite/warm/<id>.list, a file a line, in the order they sit on the
# disk (near enough: by inode).
lists="${XDG_CACHE_HOME:-$HOME/.cache}/graphite/warm"

# The files every process of the app has mapped or open, as this system sees them: a Flatpak
# app's /app and /usr are folders of /var/lib/flatpak, found from its own mount table.
files_of() {
    local pid="$1"
    {
        awk '$6 ~ /^\// { $1 = $2 = $3 = $4 = $5 = ""; sub(/^ +/, ""); print }' "/proc/$pid/maps"
        for fd in "/proc/$pid/fd"/*; do readlink "$fd"; done
    } 2>/dev/null | grep '^/' | grep -v -E ' \(deleted\)$|^/(proc|sys|dev|run|tmp)/|^/memfd:' | sort -u |
        awk -v hostinfo=/proc/self/mountinfo -v info="/proc/$pid/mountinfo" '
            BEGIN {
                # Where each device is mounted here, and how the process sees its mounts.
                while ((getline line < hostinfo) > 0) {
                    split(line, f, " ")
                    if (f[4] == "/" && !(f[3] in host)) host[f[3]] = f[5] == "/" ? "" : f[5]
                }
                while ((getline line < info) > 0) {
                    split(line, f, " ")
                    if (!(f[3] in host)) continue
                    point[++n] = f[5]
                    source[n] = host[f[3]] (f[4] == "/" ? "" : f[4])
                }
            }
            {
                best = 0
                for (i = 1; i <= n; i++) {
                    p = point[i]
                    if (p == "/" || $0 == p || substr($0, 1, length(p) + 1) == p "/")
                        if (!best || length(p) >= length(point[best])) best = i
                }
                if (!best) next
                rest = point[best] == "/" ? $0 : substr($0, length(point[best]) + 1)
                print source[best] rest
            }'
}

learn() {
    local id="$1" unit="$2"
    # Once it has finished opening.
    sleep 20
    local slice
    slice="/sys/fs/cgroup$(systemctl --user show -p ControlGroup --value app.slice 2>/dev/null)"
    [ -d "$slice" ] && [ "$slice" != /sys/fs/cgroup ] || return
    # Its own scope, and the one Flatpak moves its apps into.
    local pids
    pids="$(cat "$slice/$unit.scope/cgroup.procs" "$slice/app-flatpak-$id-"*.scope/cgroup.procs 2>/dev/null)"
    [ -n "$pids" ] || return
    mkdir -p "$lists"
    local list="$lists/${id//\//_}.list"
    for pid in $pids; do files_of "$pid"; done | sort -u |
        xargs -r -d '\n' stat -L -c '%i %s %n' 2>/dev/null |
        awk '$2 > 0 && $2 <= 268435456 { $2 = ""; print }' | sort -n | cut -d' ' -f3- > "$list.tmp"
    if [ -s "$list.tmp" ]; then mv "$list.tmp" "$list"; else rm -f "$list.tmp"; fi
}

warm() {
    [ "$(lsblk -ndo ROTA "$(findmnt -no SOURCE /)" 2>/dev/null | tr -d ' ')" = 1 ] || return
    # Only when the disk has nothing else to do, and at most a quarter of the free memory.
    ionice -c 3 -p $$ >/dev/null 2>&1
    renice -n 19 -p $$ >/dev/null 2>&1
    local budget=$(( $(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo) * 1024 / 4 ))
    for id in "$@"; do
        local list="$lists/${id//\//_}.list"
        [ -f "$list" ] || continue
        local size
        size=$(xargs -r -d '\n' -a "$list" stat -c %s 2>/dev/null | awk '{ total += $1 } END { print total + 0 }')
        [ "$size" -le "$budget" ] || break
        budget=$(( budget - size ))
        xargs -r -d '\n' -a "$list" cat -- >/dev/null 2>&1
    done
}

case "$1" in
    learn) learn "$2" "$3" ;;
    warm) shift; warm "$@" ;;
esac
