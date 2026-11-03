#!/usr/bin/env bash
# Updates everything, in a terminal: Arch Linux's packages (asks for the password), the Flatpak
# apps, and Graphite itself (a git pull of its repository; local changes are kept, and a
# pull that would clash with them is skipped). The shell reloads by itself afterwards.
# Graphite's Settings ("Update everything") and the launcher's "Update everything" run it.
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/.." && pwd)"
say() { printf '\n\033[1;33m%s\033[0m\n' "$*"; }

say "Updating the system (it asks for your password)..."
sudo pacman -Syu --noconfirm || echo "The system update didn't finish; try again later."

if command -v flatpak >/dev/null; then
    say "Updating apps (Flatpak)..."
    flatpak update -y --noninteractive || true
fi

if [ -d "$repo/.git" ]; then
    say "Updating Graphite..."
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        echo "You have changes of your own in $repo; they stay, and pulling waits until they are committed."
        git -C "$repo" status --short
    else
        git -C "$repo" pull --ff-only || echo "Graphite couldn't update (offline, or signed out of GitHub)."
    fi
    qs -c graphite ipc call settings reload >/dev/null 2>&1 || true
fi

say "All up to date."
read -rp "Press Enter to close."
