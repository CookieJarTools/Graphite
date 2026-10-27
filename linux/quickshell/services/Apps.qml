// The bar's apps: pinned ones, then running ones, each with its open windows. A window is
// matched to its app's desktop entry by its app id; pins are kept in the shell's state
// folder (pinned.json) as desktop entry ids.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    readonly property var defaultPins: ["firefox", "kitty", "org.gnome.Nautilus"]
    property var pinned: []

    // [{ key, entry, pinned, windows: [Toplevel] }] in bar order.
    readonly property var items: build(Array.from(ToplevelManager.toplevels.values), pinned)

    function entryFor(appId) {
        if (!appId) return null;
        return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId);
    }

    function build(toplevels, pins) {
        const groups = [];
        const byKey = {};
        for (const id of pins) {
            const group = { key: id, entry: entryFor(id), pinned: true, windows: [] };
            groups.push(group);
            byKey[id.toLowerCase()] = group;
        }
        for (const window of toplevels) {
            const entry = entryFor(window.appId);
            const key = (entry ? entry.id : window.appId) || "unknown";
            let group = byKey[key.toLowerCase()];
            if (!group) {
                group = { key: key, entry: entry, pinned: false, windows: [] };
                groups.push(group);
                byKey[key.toLowerCase()] = group;
            }
            group.windows.push(window);
        }
        return groups;
    }

    function nameOf(group) {
        if (group.entry) return group.entry.name;
        return group.windows.length ? group.windows[0].title : group.key;
    }

    function iconOf(group) {
        const name = group.entry ? group.entry.icon : group.key;
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // A click: start the app, bring its window forward, or step through its windows.
    function activate(group) {
        const windows = group.windows;
        if (windows.length === 0) {
            launch(group.entry);
            return;
        }
        const current = windows.findIndex(window => window.activated);
        windows[(current + 1) % windows.length].activate();
    }

    function launch(entry) {
        if (!entry) return;
        if (entry.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(Array.from(entry.command)));
        else entry.execute();
    }

    function setPinned(key, pin) {
        const without = pinned.filter(id => id !== key);
        pinned = pin ? without.concat([key]) : without;
        store.setText(JSON.stringify(pinned));
    }

    FileView {
        id: store
        path: Quickshell.statePath("pinned.json")
        blockLoading: true
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(store.text());
            root.pinned = Array.isArray(saved) ? saved : root.defaultPins;
        } catch (error) {
            root.pinned = root.defaultPins; // first run, or an unreadable file
        }
    }
}
