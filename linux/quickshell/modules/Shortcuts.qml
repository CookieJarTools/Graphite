// The keys hyprland.lua passes to the shell, as Hyprland global shortcuts
// (quickshell:<name>), and the same actions from the command line:
//   qs -c graphite ipc call launcher toggle
//   qs -c graphite ipc call switcher next
//   qs -c graphite ipc call panel toggle calendar
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

Scope {
    id: root

    required property var switcher

    function focusedScreenName() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
    }

    GlobalShortcut {
        name: "launcher"
        description: "Open or close the launcher"
        onPressed: ShellState.toggleLauncher()
    }

    GlobalShortcut {
        name: "switcher-next"
        description: "Switch to the next window (Alt+Tab)"
        onPressed: root.switcher.step(1)
    }

    GlobalShortcut {
        name: "switcher-previous"
        description: "Switch to the previous window (Alt+Shift+Tab)"
        onPressed: root.switcher.step(-1)
    }

    // Letting go of Alt; whichever of the two arrives first switches.
    GlobalShortcut {
        name: "switcher-commit"
        description: "Finish switching windows"
        onPressed: root.switcher.commit()
        onReleased: root.switcher.commit()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { ShellState.toggleLauncher(); }
        function open(): void { ShellState.closePanels(); ShellState.launcherOpen = true; }
        function close(): void { ShellState.launcherOpen = false; }
    }

    IpcHandler {
        target: "switcher"

        function next(): void { root.switcher.step(1); }
        function previous(): void { root.switcher.step(-1); }
        function commit(): void { root.switcher.commit(); }
        function cancel(): void { root.switcher.cancel(); }
    }

    IpcHandler {
        target: "panel"

        function toggle(name: string): void { ShellState.togglePanel(name, root.focusedScreenName()); }
        function close(): void { ShellState.closePanels(); }
    }
}
