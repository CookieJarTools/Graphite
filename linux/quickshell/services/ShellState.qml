pragma Singleton
// What is open across the shell (the launcher, one of the bar's panels, a menu, an app's
// window list, the tag panel, the settings window) and the windows in the order they were
// last used, which Alt+Tab follows.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    // The bar's open panel ("", "quick", "calendar" or "tray") and the screen it opened on.
    property string panel: ""
    property string panelScreen: ""

    property bool launcherOpen: false
    property bool paletteOpen: false // Alt+Space: the launcher, compact
    property bool settingsOpen: false
    property bool zoneEditorOpen: false
    property bool locked: false // the lock screen (LockScreen.qml)

    // A menu: { screen, x, y, above, items } in the screen's coordinates; items are
    // { text, action, checked, enabled, danger, separator, submenu: [items] }.
    property var menu: null

    // A pill's window list or folder (the pill's ref, see Taskbar.items), over x on the bar.
    property var popover: null
    // A folder being named in its popover (its id).
    property string renaming: ""

    // The "New tag" panel for a window: { screen, hwnd, title, x }.
    property var tagPanel: null

    // Windows, most recently active first.
    property var recent: []

    readonly property bool barBusy: panel !== "" || menu !== null || popover !== null || tagPanel !== null || renaming !== ""

    function togglePanel(name, screenName) {
        if (panel === name && panelScreen === screenName) {
            panel = "";
            return;
        }
        closeLaunchers();
        menu = null;
        popover = null;
        tagPanel = null;
        renaming = "";
        panelScreen = screenName;
        panel = name;
    }

    function closePanels() {
        panel = "";
        menu = null;
        popover = null;
        tagPanel = null;
        renaming = "";
    }

    function closeLaunchers() {
        launcherOpen = false;
        paletteOpen = false;
    }

    function toggleLauncher() {
        closePanels();
        paletteOpen = false;
        launcherOpen = !launcherOpen;
    }

    function togglePalette() {
        closePanels();
        launcherOpen = false;
        paletteOpen = !paletteOpen;
    }

    function openMenu(screenName, x, y, above, items) {
        menu = { screen: screenName, x: x, y: y, above: above, items: items };
    }

    function openPopover(screenName, ref, x) {
        panel = "";
        menu = null;
        tagPanel = null;
        popover = { screen: screenName, ref: ref, x: x };
    }

    function openTagPanel(screenName, hwnd, title, x) {
        menu = null;
        popover = null;
        tagPanel = { screen: screenName, hwnd: hwnd, title: title, x: x };
    }

    // The Control Panel, on one of its pages (ControlPanel.qml's ids: "network", "display"...).
    property string settingsPage: "network"

    function openSettings(page) {
        closePanels();
        closeLaunchers();
        if (page) settingsPage = page;
        if (settingsOpen) raise("Control Panel");
        settingsOpen = true;
    }

    // One of the shell's own windows (by its title), already open, comes to the front.
    function raise(title) {
        const toplevel = Array.from(Hyprland.toplevels.values).find(candidate => candidate.wayland && candidate.wayland.appId === "org.quickshell" && candidate.title === title);
        if (toplevel) Taskbar.focusWindow(Taskbar.addressOf(toplevel));
    }

    // Graphite's Hyprland plugin is loaded (hypr/titlebars: hyprbars with Graphite's additions):
    // Hyprland draws title bars, so the shell's windows leave closing to theirs, and a drag
    // carries on through Shift, so window zones leave the dragging to Hyprland. Asked again
    // whenever Hyprland reloads, as the plugin may have just been built.
    property bool deskPlugin: false

    Process {
        id: pluginCheck
        running: true
        command: ["hyprctl", "plugin", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.deskPlugin = this.text.includes("hyprbars")
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") pluginCheck.running = true;
        }
    }

    property bool taskManagerOpen: false

    function openTaskManager() {
        if (taskManagerOpen) raise("Task Manager");
        taskManagerOpen = true;
    }
    property bool taskViewOpen: false // Super+Tab (TaskView.qml)

    // The launcher's key hints, shown after a fast wiggle of the mouse (LauncherView).
    property bool showHints: false

    // Open windows, most recently used first; ones never activated come last.
    function windowsByRecency() {
        const open = Array.from(ToplevelManager.toplevels.values);
        const used = root.recent.filter(window => open.includes(window));
        return used.concat(open.filter(window => !used.includes(window)));
    }

    Connections {
        target: ToplevelManager

        function onActiveToplevelChanged() {
            const active = ToplevelManager.activeToplevel;
            if (active) root.recent = [active].concat(root.recent.filter(window => window !== active));
        }
    }
}
