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
        name: "palette"
        description: "Open or close the compact search (Alt+Space)"
        onPressed: { if (!ShellSettings.values || ShellSettings.values.paletteHotkey !== false) ShellState.togglePalette(); }
    }

    // Window zones (Zones.qml): the left button, Shift and Ctrl going down and up, passed on by
    // hyprland.lua without taking them from apps.
    // The button's release arrives on the same shortcut; "pointer-up" is there too, as a second
    // way in (Zones ignores a repeat). Shift and Ctrl come over IPC (zones, below).
    GlobalShortcut { name: "pointer-down"; onPressed: Zones.buttonDown(); onReleased: Zones.buttonUp() }
    GlobalShortcut { name: "pointer-up"; onPressed: Zones.buttonUp() }

    IpcHandler {
        target: "zones"

        function shift(down: bool): void { Zones.setShift(down); }
        function ctrl(down: bool): void { Zones.setCtrl(down); }
    }

    // Super + arrows: snap the focused window (Taskbar.snap).
    Variants {
        model: ["left", "right", "up", "down"]

        GlobalShortcut {
            required property string modelData
            name: "snap-" + modelData
            description: "Snap the window " + modelData
            onPressed: {
                Hyprland.refreshMonitors();
                Taskbar.snap(modelData);
            }
        }
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
        target: "palette"

        function toggle(): void { ShellState.togglePalette(); }
    }

    IpcHandler {
        target: "settings"

        function open(): void { ShellState.openSettings(); }
        function close(): void { ShellState.settingsOpen = false; }
        function tiling(on: bool): void { Taskbar.setTiling(on); }
        function autohide(on: bool): void { ShellSettings.setTaskbar("alwaysAutoHide", on); }
        function zones(): void { ShellState.zoneEditorOpen = true; }
        function apps(page: string): void { ShellState.appsPage = page || "installed"; ShellState.appsOpen = true; }
        function zoneState(): string { return JSON.stringify({ pointerDown: Zones.pointerDown, shift: Zones.shift, ctrl: Zones.ctrl }); }
    }

    // For scripts and checks: what the bar holds, and its menus opened as a right click would.
    IpcHandler {
        target: "menu"

        function bar(): void {
            const screen = Quickshell.screens[0];
            Menus.open({ screen: screen.name, x: screen.width / 2 - 100, y: screen.height - 72, above: true }, Menus.barItems());
        }
        function app(index: int): void {
            const screen = Quickshell.screens[0];
            const item = Taskbar.items[index];
            const at = { screen: screen.name, x: screen.width / 2 - 100, y: screen.height - 72, above: true };
            if (item) Menus.open(at, item.type === "folder" ? Menus.folderItems(item) : Menus.appItems(item, at, null));
        }
        function popover(index: int): void {
            const screen = Quickshell.screens[0];
            const item = Taskbar.items[index];
            if (item) ShellState.openPopover(screen.name, item.ref, screen.width / 2);
        }
        function close(): void { ShellState.closePanels(); }
    }

    // For scripts and checks: what the bar holds.
    IpcHandler {
        target: "taskbar"

        function items(): string { return JSON.stringify(Taskbar.items); }
        function windows(): string { return JSON.stringify(Taskbar.windows); }
        function settings(): string { return JSON.stringify(ShellSettings.values); }
        function rebuild(): void { Taskbar.refresh(); }        function merge(source: int, target: int): string {
            const result = Taskbar.merge(Taskbar.items[source].ref, Taskbar.items[target].ref);
            return JSON.stringify(result);
        }
        function tag(index: int, name: string): void {
            const item = Taskbar.items[index];
            if (item && item.windows.length) Taskbar.createTag(item.windows[0].hwnd, name, "");
        }    }

    IpcHandler {
        target: "panel"

        function toggle(name: string): void { ShellState.togglePanel(name, root.focusedScreenName()); }
        function close(): void { ShellState.closePanels(); }
    }
}
