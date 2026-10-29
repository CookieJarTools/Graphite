pragma Singleton
// The bar's contents and everything done to them, on Hyprland's windows: pinned apps, folders
// (named, or a category gathering every app with a launcher label), running windows one pill
// per app, and tagged windows on pills of their own. The arranging and the tags are the
// Windows version's own code (taskbar-model.js, window-tags.js, copied to lib/ by
// `npm run build:qml-lib`); a window's "hwnd" here is its Hyprland address.
//
// Hyprland has no minimising: a minimised window waits on the special workspace "minimized"
// and comes back to the workspace in front.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config
import "lib/taskbar-model.js" as Model
import "lib/window-tags.js" as Tags

Singleton {
    id: root

    readonly property var labels: Model.LABELS
    readonly property var tagColours: Tags.COLORS
    readonly property string minimizedWorkspace: "special:minimized"

    // What the bar shows (buildModel's items), rebuilt shortly after anything changes.
    property var items: []
    // Open windows as the model sees them: [{ hwnd, key, name, title, icon, zoomed, bounds, minimized, tag }]
    property var windows: []

    property var tagState: Tags.createState()

    function toplevelFor(hwnd) {
        return Array.from(Hyprland.toplevels.values).find(toplevel => root.addressOf(toplevel) === hwnd) || null;
    }

    function addressOf(toplevel) {
        const address = String(toplevel.address || "");
        return address.startsWith("0x") ? address : "0x" + address;
    }

    // The windows the bar cares about, from Hyprland's last report of each.
    function readWindows() {
        const list = [];
        for (const toplevel of Array.from(Hyprland.toplevels.values)) {
            const ipc = toplevel.lastIpcObject || {};
            if (!toplevel.wayland || !ipc.at) continue;
            const workspace = ipc.workspace ? ipc.workspace.name : "";
            if (workspace.startsWith("special:") && workspace !== root.minimizedWorkspace) continue;
            const key = Apps.keyFor(toplevel.wayland.appId || ipc.class);
            list.push({
                hwnd: root.addressOf(toplevel),
                key: key,
                name: Apps.nameFor(key),
                title: toplevel.title || ipc.title || "",
                icon: toplevel.wayland.appId || ipc.class,
                zoomed: ipc.fullscreen === 1 || ipc.fullscreen === 2,
                bounds: { x: ipc.at[0], y: ipc.at[1], width: ipc.size[0], height: ipc.size[1] },
                minimized: workspace === root.minimizedWorkspace,
                grouped: ipc.grouped ? ipc.grouped.length : 0,
                urgent: toplevel.urgent
            });
        }
        return list;
    }

    function rebuild() {
        if (!ShellSettings.loaded) return;
        const config = JSON.parse(JSON.stringify(ShellSettings.taskbar));
        config.combine = true; // one pill per app (tagged windows aside), always
        config.separate = [];
        const open = readWindows();

        // Tags: give new windows the tag remembered for their place; note where tagged ones are.
        if (Tags.resolve(config, root.tagState, open)) {
            root.pendingTagged = config.tagged;
            saveTags.restart();
        }
        for (const window of open) window.tag = Tags.tagOf(config, root.tagState, window.hwnd);

        const active = Hyprland.activeToplevel;
        const context = {
            windows: open,
            foreground: active ? root.addressOf(active) : "",
            flashing: new Set(open.filter(window => window.urgent).map(window => window.hwnd)),
            tabCounts: new Map(open.filter(window => window.grouped > 1).map(window => [window.hwnd, window.grouped])),
            apps: Apps.list,
            labels: ShellSettings.values.labels
        };
        const items = Model.buildModel(config, context);
        // Only real changes reach the bar, so its pills are not rebuilt for nothing.
        const text = JSON.stringify(items);
        if (text !== root.itemsText) {
            root.itemsText = text;
            root.items = items;
        }
        if (JSON.stringify(open) !== JSON.stringify(root.windows)) root.windows = open;
    }

    property string itemsText: ""


    property var pendingTagged: null

    // A tagged window's latest place is saved a little after it stops moving.
    Timer {
        id: saveTags
        interval: 2000
        onTriggered: {
            const tagged = root.pendingTagged;
            root.pendingTagged = null;
            if (tagged) ShellSettings.update(settings => { settings.taskbar.tagged = tagged; });
        }
    }

    Timer {
        id: rebuildSoon
        interval: 60
        onTriggered: root.rebuild()
    }

    function refresh() {
        Hyprland.refreshToplevels();
        rebuildSoon.restart();
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // An app's own minimise button: Hyprland only passes the request on.
            if (event.name === "minimized") {
                const [address, minimized] = event.data.split(",");
                if (minimized === "1") root.minimize(address.startsWith("0x") ? address : "0x" + address);
                return;
            }
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2", "activewindowv2", "fullscreen", "changefloatingmode", "togglegroup", "moveintogroup", "moveoutofgroup", "urgent", "workspace", "focusedmon"].includes(event.name)) root.refresh();
        }
        function onActiveToplevelChanged() { root.refresh(); }
    }

    // Settings (loaded a moment after start, then every change) and the installed apps.
    readonly property var settingsData: ShellSettings.values
    onSettingsDataChanged: rebuildSoon.restart()
    readonly property var appList: Apps.list
    onAppListChanged: rebuildSoon.restart()

    // Window sizes and places are not all announced; tags keep up through this. Not while a
    // fullscreen window (a game) has the screen: the shell keeps out of its way.
    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            const active = Hyprland.activeToplevel;
            if (active && active.lastIpcObject && active.lastIpcObject.fullscreen === 2) return;
            root.refresh();
        }
    }

    Component.onCompleted: refresh()

    // ---------- windows ----------

    // Brought forward and given the keyboard: back from minimised if it was, and raised as well
    // as focused, as focusing alone leaves it under an X11 window (Steam) in front of it.
    function focusWindow(hwnd) {
        const window = windows.find(candidate => candidate.hwnd === hwnd);
        if (window && window.minimized) restore(hwnd);
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${hwnd}" })`);
        Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "address:${hwnd}" })`);
    }

    function minimize(hwnd) {
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${root.minimizedWorkspace}", window = "address:${hwnd}", follow = false })`);
        refresh();
    }

    function restore(hwnd) {
        const workspace = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.name : "1";
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspace}", window = "address:${hwnd}" })`);
    }

    function closeWindow(hwnd) {
        const toplevel = toplevelFor(hwnd);
        if (toplevel && toplevel.wayland) toplevel.wayland.close();
    }

    // Super + arrows, as on Windows: left or right half of the screen (inside the bar's strip
    // and the gaps), up maximises, down restores a maximised window or else minimises it.
    function snap(direction) {
        if (ShellSettings.values && ShellSettings.values.tiling) {
            Hyprland.dispatch(`hl.dsp.focus({ direction = "${direction.slice(0, 1)}" })`); // tiled: move between them
            return;
        }
        const active = Hyprland.activeToplevel;
        if (!active || !active.lastIpcObject || !active.monitor) return;
        const hwnd = addressOf(active);
        const window = `window = "address:${hwnd}"`;
        const maximised = active.lastIpcObject.fullscreen === 1;
        const toggleMaximised = () => Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "maximized", ${window} })`);
        if (direction === "up") {
            if (!maximised) toggleMaximised();
            return;
        }
        if (direction === "down") {
            if (maximised) toggleMaximised();
            else minimize(hwnd);
            return;
        }
        if (maximised) toggleMaximised();
        const monitor = active.monitor;
        const reserved = (monitor.lastIpcObject && monitor.lastIpcObject.reserved) || [0, 0, 0, 0];
        const scale = monitor.scale || 1;
        const area = {
            x: monitor.x + reserved[0],
            y: monitor.y + reserved[1],
            width: monitor.width / scale - reserved[0] - reserved[2],
            height: monitor.height / scale - reserved[1] - reserved[3]
        };
        const gap = 8;
        const width = Math.round((area.width - gap * 3) / 2);
        const height = Math.round(area.height - gap * 2);
        const x = direction === "left" ? area.x + gap : area.x + gap * 2 + width;
        Hyprland.dispatch(`hl.dsp.window.resize({ x = ${width}, y = ${height}, exact = true, ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${x}, y = ${area.y + gap}, exact = true, ${window} })`);
        refresh();
    }

    // Apps that draw their own title bar but ask for the desktop's too (Zen, Discord): their
    // windows go without the one Hyprland draws (hypr/titlebars). hyprland.lua makes a rule of
    // each app id in ~/.config/graphite/no-titlebar, which this keeps, and reloads.
    readonly property var titleBarOff: (ShellSettings.values && ShellSettings.values.titleBarOff) || []

    function setTitleBar(appId, on) {
        const off = titleBarOff.filter(candidate => candidate !== appId).concat(on ? [] : [appId]);
        ShellSettings.set("titleBarOff", off);
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$HOME/.config/graphite" && printf "%s\\n" "$@" > "$HOME/.config/graphite/no-titlebar" && hyprctl reload >/dev/null', "sh"].concat(off));
    }

    // Floating windows (as on Windows) or tiling: hyprland.lua reads the choice from
    // ~/.config/graphite/windows for new windows; the open ones switch now.
    function setTiling(tiling) {
        ShellSettings.set("tiling", tiling);
        const mode = tiling ? "tiling" : "floating";
        Quickshell.execDetached(["sh", "-c", `mkdir -p "$HOME/.config/graphite" && printf ${mode} > "$HOME/.config/graphite/windows" && hyprctl reload`]);
        for (const toplevel of Array.from(Hyprland.toplevels.values)) {
            Hyprland.dispatch(`hl.dsp.window.float({ action = "${tiling ? "disable" : "enable"}", window = "address:${addressOf(toplevel)}" })`);
        }
        refresh();
    }

    // A pill's click: start it, bring its one window forward (or send it away when it is
    // already in front). Pills with several windows open their list instead (the bar does).
    function activate(item) {
        if (item.windows.length === 0) {
            Apps.launchKey(item.key);
            return;
        }
        const window = item.windows[0];
        if (window.focused && !window.minimized) minimize(window.hwnd);
        else focusWindow(window.hwnd);
    }

    // ---------- the arrangement ----------

    function change(work) {
        ShellSettings.update(settings => work(settings.taskbar));
    }

    function setPinned(item, pinned) {
        change(config => Model.setPinned(config, { key: item.key, name: item.name, icon: item.icon }, pinned));
    }

    function reorder(refs) {
        const visible = items;
        change(config => Model.reorder(config, refs, visible));
    }

    // Returns { id, created } for the folder the two ended up in.
    function merge(sourceRef, targetRef) {
        const visible = items;
        let result = null;
        change(config => { result = Model.merge(config, sourceRef, targetRef, visible); });
        return result;
    }

    function renameFolder(id, name) { change(config => Model.rename(config, id, name)); }
    function setFolderPinned(id, pinned) { change(config => Model.setFolderPinned(config, id, pinned)); }
    function ungroup(id) { change(config => Model.ungroup(config, id)); }
    function removeFromFolder(id, key) { change(config => Model.removeFromFolder(config, id, key)); }
    function pinCategory(label) { change(config => Model.pinCategory(config, label)); }

    function unpinCategory(label) {
        change(config => { config.items = config.items.filter(item => !(item.type === "folder" && item.label === label)); });
    }

    function categoryPinned(label) {
        return ShellSettings.taskbar.items.some(item => item.type === "folder" && item.label === label && item.pinned);
    }

    // ---------- tags ----------

    function windowFor(hwnd) {
        return windows.find(window => window.hwnd === hwnd) || null;
    }

    function tagOfWindow(hwnd) {
        const window = windowFor(hwnd);
        return window ? window.tag : null;
    }

    function tagWindow(hwnd, tagId) {
        const window = windowFor(hwnd);
        if (!window) return;
        const state = root.tagState;
        change(config => Tags.tagWindow(config, state, window, tagId));
    }

    function createTag(hwnd, name, colour) {
        const window = windowFor(hwnd);
        const state = root.tagState;
        change(config => {
            const tag = Tags.createTag(config, name, colour);
            if (window) Tags.tagWindow(config, state, window, tag.id);
        });
    }

    function deleteTag(tagId) {
        const state = root.tagState;
        change(config => Tags.deleteTag(config, state, tagId));
    }

    // The first colour no tag has yet, as a new tag's starting choice.
    function freeColour() {
        const used = new Set((ShellSettings.taskbar.tags || []).map(tag => tag.color));
        return Tags.COLORS.find(colour => !used.has(colour)) || Tags.COLORS[0];
    }

    // ---------- colours ----------

    // A tag's colour (amber is the accent), and a launcher label's.
    function tagColour(name) {
        return ({ blue: Theme.tagBlue, green: Theme.tagGreen, rose: Theme.tagRose, teal: Theme.tagTeal, violet: Theme.tagViolet, amber: Theme.accent })[name] || Theme.accent;
    }

    function labelColour(label) {
        return ({ Dev: Theme.tagBlue, Media: Theme.tagGreen, Games: Theme.tagViolet, Social: Theme.tagRose, System: Theme.tagTeal })[label] || Theme.inkMuted;
    }

    // ---------- labels ----------

    // A pill's text: the tag's name, the last part of a lone window's title, or the app's name.
    function labelOf(item) {
        if (item.type === "folder") return item.name;
        if (item.tag) return item.tag.name;
        if (item.windows.length === 1) {
            const title = item.windows[0].title || "";
            const parts = title.split(/ [-—–] /);
            return (parts.length > 1 ? parts[parts.length - 1] : title) || item.name;
        }
        return item.name;
    }
}
