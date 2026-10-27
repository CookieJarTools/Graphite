//@ pragma IconTheme Papirus-Dark
// Graphite Desk for Linux: the shell, on Hyprland. Run with `qs -c graphite` (linux/setup.sh
// links this folder to ~/.config/quickshell/graphite). Edits load live while it runs.
import QtQuick
import Quickshell
import qs.modules

ShellRoot {
    Variants {
        model: Quickshell.screens

        Backdrop {}
    }

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Launcher {}

    Switcher { id: switcher }

    Toasts {}

    Shortcuts { switcher: switcher }
}
