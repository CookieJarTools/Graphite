pragma Singleton
// What the launcher, Home and Alt+Space search through, ranked as the Windows version ranks
// (renderer.js): apps, files and folders used lately (recently-used.xbel, which GTK and Qt
// apps write), Places (the quick links), and the shell's commands. Every app and place gets a
// short alias (two or three capitals; the most used claim theirs first) that finds it when
// typed, and the switcher shows on its cards.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property var scopes: ["All", "Apps", "Files", "Folders", "Commands"]
    readonly property int rowsPerGroup: 4
    readonly property int rowsPerScope: 40
    readonly property string home: Quickshell.env("HOME")

    readonly property var settings: ShellSettings.values || ({ aliases: {}, launchCounts: {}, lastUsed: {}, quickLinks: [], recent: [], pinned: [], labels: {} })

    // ---------- commands ----------

    readonly property var commands: [
        { name: "Control Panel", alias: "cp", glyph: "preferences-system-symbolic", keys: [], run: () => ShellState.openSettings("") },
        { name: "Wi-Fi and network settings", alias: "wifi", glyph: "network-wireless-symbolic", keys: [], run: () => ShellState.openSettings("network") },
        { name: "Bluetooth and devices", alias: "bt", glyph: "bluetooth-active-symbolic", keys: [], run: () => ShellState.openSettings("devices") },
        { name: "Display settings", alias: "disp", glyph: "video-display-symbolic", keys: [], run: () => ShellState.openSettings("display") },
        { name: "Sound settings", alias: "snd", glyph: "audio-volume-high-symbolic", keys: [], run: () => ShellState.openSettings("sound") },
        { name: "Accounts and password", alias: "acc", glyph: "avatar-default-symbolic", keys: [], run: () => ShellState.openSettings("accounts") },
        { name: "Turn dark mode on or off", alias: "dark", glyph: "weather-clear-night-symbolic", keys: [], run: () => ShellSettings.update(settings => { settings.themeMode = ""; settings.dark = settings.dark === false; }) },
        { name: "Terminal", alias: "term", glyph: "utilities-terminal-symbolic", keys: ["Super", "Enter"], run: () => Quickshell.execDetached(["kitty"]) },
        { name: "Files", alias: "fm", glyph: "system-file-manager-symbolic", keys: ["Super", "E"], run: () => root.openFolder(root.home) },
        { name: "Edit window zones", alias: "zones", glyph: "view-grid-symbolic", keys: [], run: () => { ShellState.zoneEditorOpen = true; } },
        { name: "Apps", alias: "apps", glyph: "view-app-grid-symbolic", keys: [], run: () => Desktop.openApps() },
        { name: "App store", alias: "store", glyph: "system-software-install-symbolic", keys: [], run: () => Desktop.openAppStore() },
        { name: "Update everything", alias: "up", glyph: "software-update-available-symbolic", keys: [], run: () => Desktop.updateEverything() },
        { name: "Set up gaming", alias: "game", glyph: "input-gaming-symbolic", keys: [], run: () => Desktop.setUpGaming() },
        { name: "Task Manager", alias: "tm", glyph: "utilities-system-monitor-symbolic", keys: ["Ctrl", "Shift", "Esc"], run: () => { ShellState.openTaskManager(); } },
        { name: "Lock", alias: "lock", glyph: "system-lock-screen-symbolic", keys: ["Super", "L"], run: () => root.power("lock") },
        { name: "Sleep", alias: "sleep", glyph: "system-suspend-symbolic", keys: [], run: () => root.power("sleep") },
        { name: "Sign out", alias: "out", glyph: "system-log-out-symbolic", keys: [], run: () => root.power("signout") },
        { name: "Restart", alias: "reboot", glyph: "system-reboot-symbolic", keys: [], run: () => root.power("restart") },
        { name: "Shut down", alias: "off", glyph: "system-shutdown-symbolic", keys: [], run: () => root.power("shutdown") },
        { name: "Reload the desktop", alias: "rl", glyph: "view-refresh-symbolic", keys: [], run: () => Quickshell.reload(true) }
    ]

    // Lock is the shell's own lock screen; sleeping locks first, so waking asks for the password.
    function power(action) {
        if (action === "lock" || action === "sleep") ShellState.locked = true;
        if (action === "lock") return;
        const commands = {
            sleep: ["sh", "-c", "sleep 0.5; systemctl suspend"],
            signout: ["hyprctl", "dispatch", "hl.dsp.exit()"], // Hyprland's own exit dispatcher
            restart: ["systemctl", "reboot"],
            shutdown: ["systemctl", "poweroff"]
        };
        if (!commands[action]) return;
        if (action === "sleep") Quickshell.execDetached(commands[action]);
        else Quickshell.execDetached(["sh", "-c", Sounds.command("logout") + '; exec "$@"', "sh"].concat(commands[action]));
    }

    // ---------- recent files and folders ----------

    // [{ kind: "file" | "folder", target, name, folder, time }], newest first.
    property var recentItems: []

    FileView {
        id: xbel
        path: root.home + "/.local/share/recently-used.xbel"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readRecent(text())
    }

    function readRecent(text) {
        const found = [];
        const seen = {};
        const pattern = /<bookmark\s+href="file:\/\/([^"]+)"[^>]*?(?:modified|visited)="([^"]+)"[\s\S]*?<\/bookmark>/g;
        let match;
        while ((match = pattern.exec(text)) !== null) {
            const target = decodeURIComponent(match[1]);
            if (seen[target]) continue;
            seen[target] = true;
            const folder = /mime:mime-type\s+type="inode\/directory"/.test(match[0]);
            const parts = target.split("/");
            found.push({
                kind: folder ? "folder" : "file",
                target: target,
                name: parts[parts.length - 1] || target,
                folder: tilde(parts.slice(0, -1).join("/") || "/"),
                time: Date.parse(match[2]) || 0
            });
        }
        recentItems = found.sort((first, second) => second.time - first.time).slice(0, 150);
    }

    function tilde(path) {
        return path === home ? "~" : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    function expand(path) {
        return path === "~" ? home : path.startsWith("~/") ? home + path.slice(1) : path;
    }

    // ---------- aliases ----------

    // Two or three capitals from the name: "Prime Video" -> PV, "AppData" -> AD, "Steam" -> ST.
    function baseAlias(name) {
        const words = String(name).replace(/([a-z])([A-Z])/g, "$1 $2").split(/[^A-Za-z0-9]+/).filter(Boolean);
        if (words.length >= 2) return words.slice(0, 3).map(word => word[0]).join("").toUpperCase();
        return (words[0] || String(name)).slice(0, 2).toUpperCase();
    }

    readonly property var places: (settings.quickLinks || []).map(path => ({
        path: path,
        name: path === "~" ? "Home" : path.split("/").filter(Boolean).pop() || path
    }))

    readonly property var apps: Array.from(DesktopEntries.applications.values).filter(entry => !entry.noDisplay)

    // id -> alias; a taken alias tries the first letter with each later one, then a number.
    readonly property var aliases: {
        const index = {};
        const taken = {};
        for (const command of commands) taken[command.alias.toUpperCase()] = true;
        const assign = (id, name) => {
            const base = (settings.aliases || {})[id] || baseAlias(name);
            const letters = String(name).replace(/[^A-Za-z0-9]/g, "").toUpperCase();
            let alias = base;
            for (let letter = 2; taken[alias] && letter < letters.length; letter++) alias = letters[0] + letters[letter];
            for (let suffix = 2; taken[alias]; suffix++) alias = base + suffix;
            taken[alias] = true;
            index[id] = alias;
        };
        for (const place of places) assign("place:" + place.path, place.name);
        const counts = settings.launchCounts || {};
        const usage = entry => counts[entry.id] || 0;
        apps.slice().sort((first, second) => usage(second) - usage(first) || first.name.localeCompare(second.name))
            .forEach(entry => assign(entry.id, entry.name));
        return index;
    }

    function aliasOf(id) {
        return aliases[id] || "";
    }

    // ---------- items ----------

    function appItem(entry) {
        return { kind: "Apps", id: entry.id, name: entry.name, alias: aliasOf(entry.id), entry: entry, icon: entry.icon, time: (settings.lastUsed || {})[entry.id] || 0 };
    }

    function placeItems() {
        return places.map(place => ({ kind: "Folders", id: "place:" + place.path, name: place.name, alias: aliasOf("place:" + place.path), path: place.path, target: expand(place.path) }));
    }

    function recentOfKind(kind) {
        return recentItems.filter(item => item.kind === kind).map(item => ({
            kind: kind === "file" ? "Files" : "Folders",
            id: "recent:" + item.target,
            name: item.name,
            alias: kind === "file" ? (item.name.includes(".") ? item.name.split(".").pop().toUpperCase().slice(0, 6) : "") : baseAlias(item.name),
            path: item.folder,
            target: item.target,
            time: item.time
        }));
    }

    function commandItems() {
        return commands.map(command => ({ kind: "Commands", id: "command:" + command.name, name: command.name, alias: command.alias, command: command, glyph: command.glyph }));
    }

    function scoreItem(item, query) {
        const lower = query.toLowerCase();
        const name = item.name.toLowerCase();
        const alias = (item.alias || "").toLowerCase();
        if (alias && alias === lower) return 4;
        if (name.startsWith(lower) || (alias && alias.startsWith(lower))) return 3;
        const index = name.indexOf(lower);
        if (index > 0 && /[^a-z0-9]/.test(name[index - 1])) return 2;
        if (index >= 0) return 1;
        // An app's other names: its kind ("Web Browser") and keywords.
        if (item.entry && ((item.entry.genericName || "").toLowerCase().includes(lower) || Array.from(item.entry.keywords).some(keyword => keyword.toLowerCase().startsWith(lower)))) return 1;
        return 0;
    }

    // [{ kind, total, items }] for a query, in one scope or all (a few rows of each kind).
    function groups(query, scope) {
        const all = [
            { kind: "Apps", items: apps.map(appItem) },
            { kind: "Files", items: recentOfKind("file") },
            { kind: "Folders", items: placeItems().concat(recentOfKind("folder")) },
            { kind: "Commands", items: commandItems() }
        ];
        const counts = settings.launchCounts || {};
        const usage = item => (item.entry && counts[item.entry.id]) || 0;
        return all
            .filter(group => scope === "All" || scope === group.kind)
            .map(group => {
                const matches = group.items
                    .map(item => ({ item: item, score: scoreItem(item, query) }))
                    .filter(match => match.score > 0)
                    .sort((first, second) => second.score - first.score || usage(second.item) - usage(first.item) || (second.item.time || 0) - (first.item.time || 0) || first.item.name.localeCompare(second.item.name));
                return { kind: group.kind, total: matches.length, items: matches.slice(0, scope === "All" ? rowsPerGroup : rowsPerScope).map(match => match.item) };
            });
    }

    // Apps opened lately and files used lately, newest first.
    function recentRows(count) {
        const byId = {};
        for (const entry of apps) byId[entry.id] = entry;
        const recentApps = (settings.recent || []).filter(item => item.kind === "app" && byId[item.id]).map(item => appItem(byId[item.id]));
        return recentApps.concat(recentOfKind("file")).sort((first, second) => (second.time || 0) - (first.time || 0)).slice(0, count);
    }

    // Every installed app, the most used this month first (Apps.usesThisMonth), then by name:
    // the launcher's list while nothing is typed.
    function appsByUse() {
        return apps.map(entry => ({ entry: entry, uses: Apps.usesThisMonth(entry.id) }))
            .sort((first, second) => second.uses - first.uses || first.entry.name.localeCompare(second.entry.name))
            .map(pair => appItem(pair.entry));
    }

    function pinnedApps() {
        return (settings.pinned || []).map(id => DesktopEntries.byId(id)).filter(Boolean).map(appItem);
    }

    // ---------- opening ----------

    function open(item, asAdmin) {
        if (!item) return;
        if (item.kind === "Apps") {
            if (asAdmin) Apps.runAsAdmin(item.id);
            else Apps.launch(item.entry);
        } else if (item.kind === "Commands") {
            item.command.run();
        } else if (item.kind === "Folders") {
            openFolder(item.target);
        } else {
            openFile(item.target);
        }
    }

    function openFolder(path) {
        openPath(expand(path), true);
    }

    function openFile(path) {
        openPath(path, false);
    }

    // A missing file or folder says so in a notification rather than doing nothing.
    function openPath(path, folder) {
        const name = path.split("/").filter(Boolean).pop() || path;
        const opener = folder ? "nautilus --new-window \"$1\"" : "xdg-open \"$1\"";
        Quickshell.execDetached(["sh", "-c", `if [ -e "$1" ]; then ${opener} >/dev/null 2>&1 & else notify-send -a "Graphite Desk" "Can't find ${name.replace(/["$`\\]/g, "")}" "$1"; fi`, "sh", path]);
    }

    function searchWeb(query) {
        Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(query)]);
    }

    // ---------- the launcher's own pins and labels ----------

    function isPinned(id) {
        return (settings.pinned || []).includes(id);
    }

    function setPinned(id, pinned) {
        ShellSettings.update(values => {
            values.pinned = values.pinned.filter(candidate => candidate !== id);
            if (pinned) values.pinned.push(id);
        });
    }

    function labelOf(id) {
        return (settings.labels || {})[id] || "";
    }

    function setLabel(id, label) {
        ShellSettings.update(values => {
            if (label) values.labels[id] = label;
            else delete values.labels[id];
        });
    }

    // An app row's right-click menu: as administrator, pins (bar and launcher), its label.
    function appMenu(item) {
        const onBar = (ShellSettings.taskbar.items || []).some(stored => stored.type === "app" && stored.key === item.id && stored.pinned);
        const label = labelOf(item.id);
        return [
            { text: "Run as administrator", visible: Apps.canRunAsAdmin(item.id), action: () => Apps.runAsAdmin(item.id) },
            { separator: true, visible: Apps.canRunAsAdmin(item.id) },
            { text: onBar ? "Unpin from taskbar" : "Pin to taskbar", action: () => Taskbar.setPinned({ key: item.id, name: item.name, icon: item.icon }, !onBar) },
            { text: isPinned(item.id) ? "Unpin" : "Pin", action: () => setPinned(item.id, !isPinned(item.id)) },
            {
                text: "Label",
                submenu: Taskbar.labels.map(name => ({ text: name, checked: label === name, colour: Taskbar.labelColour(name), action: () => setLabel(item.id, name) }))
                    .concat([{ separator: true }, { text: "None", checked: !label, action: () => setLabel(item.id, "") }])
            },
            { separator: true, visible: Desktop.canRemove(item.id) },
            { text: "Uninstall", danger: true, visible: Desktop.canRemove(item.id), action: () => Desktop.uninstall(item.id) }
        ];
    }

    // The matched part of a name in the accent colour (for Text.StyledText).
    function mark(text, match) {
        const escape = value => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const value = String(text);
        const index = match ? value.toLowerCase().indexOf(match.toLowerCase()) : -1;
        if (index < 0) return escape(value);
        return escape(value.slice(0, index)) + `<font color="${Theme.accent}">` + escape(value.slice(index, index + match.length)) + "</font>" + escape(value.slice(index + match.length));
    }

    // "now", "5m", "3h", "Yesterday", "4d", "12 Oct".
    function timeAgo(time) {
        if (!time) return "";
        const minutes = Math.round((Date.now() - time) / 60000);
        if (minutes < 1) return "now";
        if (minutes < 60) return minutes + "m";
        const hours = Math.round(minutes / 60);
        if (hours < 24) return hours + "h";
        const days = Math.round(hours / 24);
        return days === 1 ? "Yesterday" : days < 7 ? days + "d" : Qt.formatDate(new Date(time), "d MMM");
    }
}
