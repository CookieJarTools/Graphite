pragma Singleton
// The installed apps (desktop entries): finding a window's app by its app id, their names and
// icons, starting them (also as administrator, through polkit) and remembering what was used,
// which the launcher ranks and lists by.

import QtQuick
import Quickshell

Singleton {
    id: root

    // [{ id, name, icon }], the shape taskbar-model.js takes; NoDisplay entries left out.
    readonly property var list: Array.from(DesktopEntries.applications.values)
        .filter(entry => !entry.noDisplay)
        .map(entry => ({ id: entry.id, name: entry.name, icon: entry.icon }))

    function entryFor(appId) {
        if (!appId) return null;
        return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId);
    }

    // The key a window's app goes by on the bar: its desktop entry's id, or its app id.
    function keyFor(appId) {
        const entry = entryFor(appId);
        return (entry ? entry.id : appId) || "unknown";
    }

    function nameFor(key) {
        const entry = DesktopEntries.byId(key);
        return entry ? entry.name : key;
    }

    function iconFor(key, fallbackIcon) {
        const entry = DesktopEntries.byId(key);
        return Quickshell.iconPath((entry && entry.icon) || fallbackIcon || key, "application-x-executable");
    }

    function launchKey(key) {
        const entry = DesktopEntries.byId(key);
        if (entry) launch(entry);
    }

    function launch(entry) {
        if (!entry) return;
        if (entry.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(Array.from(entry.command)));
        // Through system/launch.sh: if the app can't start, it says why.
        else if (entry.command.length) Quickshell.execDetached({
            command: ["setsid", "bash", Quickshell.shellDir + "/../system/launch.sh", entry.name, entry.id].concat(Array.from(entry.command)),
            workingDirectory: entry.workingDirectory || Quickshell.env("HOME")
        });
        else entry.execute();
        noteUsed(entry.id);
    }

    function canRunAsAdmin(key) {
        const entry = DesktopEntries.byId(key);
        return entry !== null && entry.command.length > 0;
    }

    // As root, after polkit asks for the password. The app is pointed at this session's
    // display (by its full path, as root has a runtime folder of its own).
    function runAsAdmin(key) {
        const entry = DesktopEntries.byId(key);
        if (!entry) return;
        const command = Array.from(entry.command);
        const display = "WAYLAND_DISPLAY=" + Quickshell.env("XDG_RUNTIME_DIR") + "/" + Quickshell.env("WAYLAND_DISPLAY");
        const environment = ["env", display, "XDG_RUNTIME_DIR=/tmp/graphite-root", "QT_QPA_PLATFORM=wayland", "GDK_BACKEND=wayland"];
        if (Quickshell.env("LIBGL_ALWAYS_SOFTWARE")) environment.push("LIBGL_ALWAYS_SOFTWARE=1");
        const inner = entry.runInTerminal ? ["kitty", "-e"].concat(command) : command;
        Quickshell.execDetached(["sh", "-c", "mkdir -p -m 700 /tmp/graphite-root 2>/dev/null; exec \"$@\"", "sh", "pkexec"].concat(environment, inner));
        noteUsed(entry.id);
    }

    // What the launcher ranks by: how often, and when last; the newest eight are Recent.
    function noteUsed(id) {
        ShellSettings.update(settings => {
            settings.launchCounts[id] = (settings.launchCounts[id] || 0) + 1;
            settings.lastUsed[id] = Date.now();
            settings.recent = [{ kind: "app", id: id, time: Date.now() }]
                .concat(settings.recent.filter(item => !(item.kind === "app" && item.id === id)))
                .slice(0, 8);
        });
    }
}
