pragma Singleton
// Keyboard shortcuts for the Control Panel's Shortcuts page: the desktop's own (hyprland.lua
// sets their defaults) and ones you add to open an app. A changed one is kept in settings.json
// (shortcuts: { id: "SUPER + E" }, "" for none; appShortcuts: [{ keys, id, name }]) and
// written into desk.lua (Displays.write) as Hyprland Lua: the default unbound, the new keys bound.

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string system: Quickshell.shellDir + "/../system"

    // Each shortcut: what it does, its keys by default, and what Hyprland runs.
    readonly property var actions: [
        { id: "taskview", label: "Show all windows", keys: "SUPER + Tab", lua: `hl.dsp.global("quickshell:taskview")` },
        { id: "files", label: "Open Files", keys: "SUPER + E", lua: `hl.dsp.exec_cmd("nautilus")` },
        { id: "terminal", label: "Open the terminal", keys: "SUPER + Return", lua: `hl.dsp.exec_cmd("kitty")` },
        { id: "taskmanager", label: "Task Manager", keys: "CTRL + SHIFT + Escape", lua: `hl.dsp.global("quickshell:taskmanager")` },
        { id: "palette", label: "Quick search", keys: "ALT + space", lua: `hl.dsp.global("quickshell:palette")` },
        { id: "lock", label: "Lock the screen", keys: "SUPER + L", lua: `hl.dsp.global("quickshell:lock")` },
        { id: "screenshot", label: "Screenshot", keys: "Print", lua: `hl.dsp.exec_cmd("bash ${system}/screenshot.sh screen")` },
        { id: "area", label: "Screenshot of an area", keys: "SUPER + SHIFT + S", lua: `hl.dsp.exec_cmd("bash ${system}/screenshot.sh area")` },
        { id: "close", label: "Close the window", keys: "SUPER + Q", lua: `hl.dsp.window.close()` },
        { id: "maximise", label: "Maximise the window", keys: "SUPER + F", lua: `hl.dsp.window.fullscreen({ mode = "maximized" })` },
        { id: "fullscreen", label: "Full screen", keys: "SUPER + SHIFT + F", lua: `hl.dsp.window.fullscreen({ mode = "fullscreen" })` },
        { id: "float", label: "Float or tile the window", keys: "SUPER + V", lua: `hl.dsp.window.float()` },
        { id: "snap-left", label: "Snap to the left", keys: "SUPER + left", lua: `hl.dsp.global("quickshell:snap-left")` },
        { id: "snap-right", label: "Snap to the right", keys: "SUPER + right", lua: `hl.dsp.global("quickshell:snap-right")` },
        { id: "snap-up", label: "Maximise or restore", keys: "SUPER + up", lua: `hl.dsp.global("quickshell:snap-up")` },
        { id: "snap-down", label: "Restore or minimise", keys: "SUPER + down", lua: `hl.dsp.global("quickshell:snap-down")` }
    ]

    // Shown, but not changed here.
    readonly property var fixed: [
        { label: "Search", keys: "SUPER" },
        { label: "Switch windows", keys: "ALT + Tab" },
        { label: "Move a window", keys: "SUPER + drag" }
    ]

    readonly property var chosen: ShellSettings.values ? (ShellSettings.values.shortcuts || {}) : ({})
    readonly property var appShortcuts: ShellSettings.values ? (ShellSettings.values.appShortcuts || []) : []

    function keysFor(action) {
        return chosen[action.id] !== undefined ? chosen[action.id] : action.keys;
    }

    // "SUPER + SHIFT + S" as people write it: "Windows + Shift + S".
    function shown(keys) {
        if (!keys) return "None";
        const names = { SUPER: "Windows", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", Return: "Enter", Escape: "Esc", space: "Space", Print: "Print Screen", left: "Left", right: "Right", up: "Up", down: "Down", Tab: "Tab" };
        return keys.split(" + ").map(part => names[part] || part).join(" + ");
    }

    // Which shortcut already uses these keys (so one isn't set twice).
    function takenBy(keys, exceptId) {
        const action = actions.find(candidate => candidate.id !== exceptId && keysFor(candidate) === keys);
        if (action) return action.label;
        const app = appShortcuts.find(candidate => candidate.keys === keys && candidate.id !== exceptId);
        if (app) return "Open " + app.name;
        const fixedOne = fixed.find(candidate => candidate.keys === keys);
        return fixedOne ? fixedOne.label : "";
    }

    function set(id, keys) {
        ShellSettings.update(settings => {
            settings.shortcuts = Object.assign({}, settings.shortcuts || {});
            const action = actions.find(candidate => candidate.id === id);
            if (action && action.keys === keys) delete settings.shortcuts[id];
            else settings.shortcuts[id] = keys;
        });
        Displays.write();
    }

    function addApp(keys, id, name) {
        ShellSettings.update(settings => {
            settings.appShortcuts = (settings.appShortcuts || []).filter(candidate => candidate.id !== id).concat([{ keys: keys, id: id, name: name }]);
        });
        Displays.write();
    }

    function removeApp(id) {
        ShellSettings.update(settings => {
            settings.appShortcuts = (settings.appShortcuts || []).filter(candidate => candidate.id !== id);
        });
        Displays.write();
    }

    function resetAll() {
        ShellSettings.update(settings => {
            settings.shortcuts = {};
        });
        Displays.write();
    }

    function lua(text) {
        return JSON.stringify(text);
    }

    // The lines for desk.lua.
    function luaLines() {
        const lines = [];
        for (const action of actions) {
            if (chosen[action.id] === undefined) continue;
            lines.push(`pcall(hl.unbind, ${lua(action.keys)})`);
            if (chosen[action.id]) lines.push(`hl.bind(${lua(chosen[action.id])}, ${action.lua})`);
        }
        for (const app of appShortcuts) {
            lines.push(`hl.bind(${lua(app.keys)}, hl.dsp.exec_cmd(${lua("qs -c graphite ipc call apps launch " + app.id)}))`);
        }
        return lines;
    }
}
