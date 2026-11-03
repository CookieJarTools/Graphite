//@ pragma IconTheme Papirus-Dark
// Graphite for Linux: the shell, on Hyprland. Run with `qs -c graphite` (linux/setup.sh
// links this folder to ~/.config/quickshell/graphite). Edits load live while it runs.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules
import qs.services

ShellRoot {
    id: root

    // The colours follow the Dark mode setting, the shell's and the apps' (linux/gtk/apply.sh):
    // dark, light, or with the time of day (light from 7 in the morning to 7 in the evening).
    property int hour: new Date().getHours()
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.hour = new Date().getHours()
    }
    readonly property bool dark: !ShellSettings.values ? true
        : ShellSettings.values.themeMode === "auto" ? (root.hour < 7 || root.hour >= 19)
        : ShellSettings.values.dark !== false
    Binding {
        target: Theme
        property: "dark"
        value: root.dark
    }
    onDarkChanged: Desktop.applyLook(dark)
    Component.onCompleted: {
        Desktop.applyLook(dark);
        Desktop.register(); // downloaded apps open in the installer
        // Services that work in the background from the start (singletons only exist once
        // used): idle and sleep (hypridle), night light and the screens, update checks, drives,
        // the security sweep.
        Power.refresh();
        Displays.refresh();
        Updates.lastChecked;
        Drives.disks; // keeps Files' Drives place up to date
        Security.every; // the security sweep, on its schedule
    }

    // Bluetooth pairing needs an agent to accept it on the computer's side: this one (BlueZ's
    // own, kept running) pairs without codes, as Windows does for mice, headphones and most
    // keyboards.
    Process {
        running: true
        command: ["bluetoothctl"]
        stdinEnabled: true
        stdout: SplitParser {}
        onStarted: write("agent NoInputNoOutput\ndefault-agent\n")
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

    ControlPanel {}
    PasswordPrompt {}
    TaskManager {}
    TaskView {}
    CaptureTool {}
    VolumePopup {}

    LockScreen {}

    Shortcuts { switcher: switcher }
}
