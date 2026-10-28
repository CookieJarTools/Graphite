//@ pragma IconTheme Papirus-Dark
// Graphite Desk for Linux: the shell, on Hyprland. Run with `qs -c graphite` (linux/setup.sh
// links this folder to ~/.config/quickshell/graphite). Edits load live while it runs.
import QtQuick
import Quickshell
import qs.config
import qs.modules
import qs.services

ShellRoot {
    id: root

    // The colours follow the Dark mode setting, the shell's and the apps' (linux/gtk/apply.sh).
    readonly property bool dark: !ShellSettings.values || ShellSettings.values.dark !== false
    Binding {
        target: Theme
        property: "dark"
        value: root.dark
    }
    onDarkChanged: Desktop.applyLook(dark)
    Component.onCompleted: {
        Desktop.applyLook(dark);
        Desktop.register(); // downloaded apps open in the installer
    }

    Variants {
        model: Quickshell.screens

        Backdrop {}
    }

    Variants {
        model: Quickshell.screens

        Home {}
    }

    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Variants {
        model: Quickshell.screens

        Menu {}
    }

    Variants {
        model: Quickshell.screens

        ZonesOverlay {}
    }

    ZoneEditor {}

    Launcher {}

    Switcher { id: switcher }

    Toasts {}

    SettingsWindow {}

    AppsWindow {}

    LockScreen {}

    Shortcuts { switcher: switcher }
}
