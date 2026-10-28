pragma Singleton
// Everything the shell keeps between sessions, in its state folder as settings.json (the
// Windows version's settings.json, the parts that apply here):
//   taskbar   { combine, separate, items, showLabels, alwaysAutoHide, autoHideWhenMaximised,
//               tags, tagged }  (taskbar-model.js and window-tags.js describe these)
//   pinned    the launcher's Pinned apps (desktop entry ids)
//   labels    { entryId: "Dev" | "Media" | "Games" | "Social" | "System" }
//   aliases   { entryId: "XX" }, the user's own launcher aliases
//   recent    [{ kind: "app" | "path", id, time }], newest first
//   launchCounts, lastUsed   { entryId: number }
//   quickLinks   folders listed as Places in the launcher (~ for home)
//   showHome     Home on an empty screen
//   dark         the dark colours (the light ones otherwise)
//   tiling       windows tile (Hyprland's way) rather than float (Windows' way)
//   smoothText   MacType-like text: FreeType's stem darkening
//   paletteHotkey   Alt+Space opens the compact search
//   notificationsSeen   when the calendar was last opened (ms)
// Changes go through update(), which saves a moment later.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Null until read from the file, a moment after the shell starts.
    property var values: null
    readonly property var taskbar: values ? values.taskbar : ({ items: [], tags: [], tagged: [], showLabels: true })
    property bool loaded: false

    function defaults() {
        return {
            taskbar: {
                combine: true,
                separate: [],
                items: ["firefox", "kitty", "org.gnome.Nautilus"].map(key => ({ type: "app", key: key, pinned: true })),
                showLabels: true,
                alwaysAutoHide: false,
                autoHideWhenMaximised: false,
                tags: [],
                tagged: []
            },
            pinned: [],
            labels: {},
            aliases: {},
            recent: [],
            launchCounts: {},
            lastUsed: {},
            quickLinks: ["~", "~/Downloads", "~/Documents", "~/Pictures", "~/.config"],
            showHome: true,
            dark: true,
            tiling: false,
            smoothText: true,
            paletteHotkey: true,
            notificationsSeen: 0
        };
    }

    // Runs change(copy) on a copy of the settings, then keeps the copy and saves it.
    function update(change) {
        const copy = JSON.parse(JSON.stringify(values));
        change(copy);
        values = copy;
        saveSoon.restart();
    }

    function set(key, value) {
        update(settings => { settings[key] = value; });
    }

    function setTaskbar(key, value) {
        update(settings => { settings.taskbar[key] = value; });
    }

    FileView {
        id: store
        path: Quickshell.statePath("settings.json")
        blockLoading: true
    }

    // The first version kept only the bar's pins, in pinned.json.
    FileView {
        id: oldPins
        path: Quickshell.statePath("pinned.json")
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: saveSoon
        interval: 400
        onTriggered: store.setText(JSON.stringify(root.values, null, 2))
    }

    Component.onCompleted: {
        const settings = defaults();
        let saved = null;
        try {
            saved = JSON.parse(store.text());
        } catch (error) {
            saved = null; // first run, or an unreadable file
        }
        if (saved && typeof saved === "object") {
            for (const key of Object.keys(settings)) {
                if (saved[key] === undefined) continue;
                settings[key] = key === "taskbar" ? Object.assign(settings.taskbar, saved.taskbar) : saved[key];
            }
        } else {
            try {
                const pins = JSON.parse(oldPins.text());
                if (Array.isArray(pins)) settings.taskbar.items = pins.map(key => ({ type: "app", key: key, pinned: true }));
            } catch (error) {
                // no earlier pins
            }
        }
        values = settings;
        loaded = true;
    }
}
