#!/usr/bin/env bash
# The person's half of "Update everything" (the system half is graphite-update.service): their
# Flatpak apps, the Ubuntu space's apps (.deb installs, linux/apps), and Graphite Desk itself (a
# git pull of /opt/graphite-desk; changes of their own are kept, and a pull that would clash
# with them waits). It prints one line per step for the Control Panel; the shell reloads after.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

if command -v flatpak >/dev/null; then
    echo "STEP Updating your apps"
    flatpak update --user -y --noninteractive >/dev/null 2>&1 || true
fi

if command -v distrobox >/dev/null && podman container exists apps 2>/dev/null; then
    echo "STEP Updating Ubuntu apps"
    distrobox upgrade apps >/dev/null 2>&1 || true
fi

if [ -d "$repo/.git" ]; then
    echo "STEP Updating Graphite Desk"
    if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
        echo "NOTE Graphite Desk wasn't updated because it has uncommitted changes."
    else
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" timeout 120 git -C "$repo" pull --ff-only -q </dev/null >/dev/null 2>&1 || echo "NOTE Graphite Desk couldn't update. You may be offline or signed out of GitHub."
    fi
fi
# Title bars for the Hyprland just installed, ready for the next sign-in (hypr/titlebars).
bash "$repo/linux/hypr/titlebars/build.sh" >/dev/null 2>&1 || true
echo "DONE"
