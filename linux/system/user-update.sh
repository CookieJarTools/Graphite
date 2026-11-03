#!/usr/bin/env bash
# The person's half of "Update everything" (the system half is graphite-update.service): their
# Flatpak apps, the Ubuntu space's apps (.deb installs, linux/apps), apps from their makers (Unity
# Hub), and Graphite itself (a git pull of /opt/graphite-desk; changes of their own are
# kept, and a pull that would clash with them waits). One line per step, for the Control Panel,
# printed and written to ~/.local/state/graphite/user-update: the Control Panel starts it apart
# from the shell and follows that file, as the shell reloads part way through when Graphite
# Desk itself changes.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
progress="${XDG_STATE_HOME:-$HOME/.local/state}/graphite/user-update"
mkdir -p "$(dirname "$progress")"
echo "START $$ $(date +%s)" > "$progress"
say() { echo "$*"; echo "$*" >> "$progress"; }
trap 'say "DONE $(date +%s)"' EXIT

if command -v flatpak >/dev/null; then
    say "STEP Updating your apps"
    flatpak update --user -y --noninteractive >/dev/null 2>&1 || true
fi

if command -v distrobox >/dev/null && podman container exists apps 2>/dev/null; then
    say "STEP Updating Ubuntu apps"
    distrobox upgrade apps >/dev/null 2>&1 || true
fi

# Apps from their makers (install-app.sh --vendor): only when there's a newer one, and not
# while it's open.
if grep -qsx 'kind=vendor' "$HOME/.local/share/graphite/apps/unityhub"; then
    say "STEP Updating Unity Hub"
    bash "$repo/linux/apps/install-app.sh" --vendor unityhub --update >/dev/null 2>&1 || true
fi

if [ -d "$repo/.git" ]; then
    say "STEP Updating Graphite"
    if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
        say "NOTE Graphite wasn't updated because it has uncommitted changes."
    else
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" timeout 120 git -C "$repo" pull --ff-only -q </dev/null >/dev/null 2>&1 || say "NOTE Graphite couldn't update. You may be offline or signed out of GitHub."
    fi
fi
# Title bars for the Hyprland just installed, ready for the next sign-in (hypr/titlebars).
bash "$repo/linux/hypr/titlebars/build.sh" >/dev/null 2>&1 || true
