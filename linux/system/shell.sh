#!/usr/bin/env bash
# The shell (the bar, launcher and Control Panel: quickshell/), kept running as Windows keeps its
# taskbar: hyprland.lua starts this at sign-in, and when the shell stops (a crash, or the
# computer running out of memory with a big game open) it starts again a few seconds later. A
# shell started by hand (vm/restart-shell.sh) is left to run, and watched the same way. Three
# stops within ten seconds of starting, one after another, and it rests a minute, as a change
# that breaks the shell would only go round. It ends with Hyprland (signing out).
quick=0
while hyprctl -j version >/dev/null 2>&1; do
    if qs list -c graphite 2>/dev/null | grep -q 'Process ID'; then
        quick=0
        sleep 2
        continue
    fi
    started=$SECONDS
    qs -c graphite --no-duplicate >/dev/null 2>&1 </dev/null
    if [ $((SECONDS - started)) -lt 10 ]; then quick=$((quick + 1)); else quick=0; fi
    if [ "$quick" -ge 3 ]; then
        quick=0
        sleep 60
    else
        # A moment first, so one started by hand gets there before this does.
        sleep 3
    fi
done
