#!/usr/bin/env bash
# Starts an app for the launcher and the taskbar (services/Apps.qml), keeping what it says in
# ~/.cache/graphite/apps/<id>.log. When it closes with an error within 20 seconds (so it
# never really opened), a notification says so in its own words, and the failure is noted in
# ~/.cache/graphite/apps/failures for the Control Panel's Troubleshoot.
#
#   launch.sh NAME ID COMMAND...
name="$1"
id="$2"
shift 2
logs="${XDG_CACHE_HOME:-$HOME/.cache}/graphite/apps"
mkdir -p "$logs"
log="$logs/${id//\//_}.log"
# The last few runs only.
[ -f "$log" ] && [ "$(wc -l < "$log")" -gt 400 ] && tail -200 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
echo "== $(date '+%F %T') $*" >> "$log"

started=$(date +%s)
unit="app-graphite-${id//[^a-zA-Z0-9]/_}-$$"
# What it reads from the disk, noted once it is up, so that next time it's in memory before it's
# asked for (warm.sh).
setsid bash "$(dirname "$0")/warm.sh" learn "$id" "$unit" >/dev/null 2>&1 < /dev/null &
# In its own place in the system (a scope), so it carries on if the desktop restarts.
systemd-run --user --scope --quiet --slice=app.slice --unit="$unit" -- "$@" >> "$log" 2>&1 < /dev/null
code=$?
lasted=$(( $(date +%s) - started ))
[ "$code" -eq 0 ] || [ "$lasted" -ge 20 ] && exit 0

# What it said last that sounds like the reason, else its last words.
reason="$(sed -n '/^== /h; /^== /!H; ${x; p}' "$log" | grep -iE 'error|fail|cannot|can.t|unable|not found|denied|missing|segmentation|abort' | tail -1)"
[ -n "$reason" ] || reason="$(tail -1 "$log")"
[ "${reason#== }" != "$reason" ] && reason=""
reason="${reason:0:200}"
printf '%s\t%s\t%s\n' "$(date +%s)" "$name" "${reason:-It closed straight away (code $code).}" >> "$logs/failures"
notify-send -a "Graphite" -i dialog-warning "$name didn't open" "${reason:-It closed straight away.} Open Troubleshoot in the Control Panel for help." 2>/dev/null
exit 0
