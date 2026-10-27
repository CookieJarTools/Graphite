// What is open across the shell (the launcher, the switcher, one of the bar's panels) and
// the windows in the order they were last used, which Alt+Tab follows.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // The bar's open panel ("", "quick", "calendar" or "tray") and the screen it opened on.
    property string panel: ""
    property string panelScreen: ""

    property bool launcherOpen: false

    // An app's right-click menu on the bar: its group (see Apps.items), where it opened.
    property var appMenu: null
    property string appMenuScreen: ""
    property real appMenuX: 0

    // Windows, most recently active first.
    property var recent: []

    function togglePanel(name, screenName) {
        if (panel === name && panelScreen === screenName) {
            panel = "";
            return;
        }
        launcherOpen = false;
        appMenu = null;
        panelScreen = screenName;
        panel = name;
    }

    function closePanels() {
        panel = "";
        appMenu = null;
    }

    function toggleLauncher() {
        closePanels();
        launcherOpen = !launcherOpen;
    }

    function openAppMenu(group, screenName, x) {
        panel = "";
        appMenuScreen = screenName;
        appMenuX = x;
        appMenu = group;
    }

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
