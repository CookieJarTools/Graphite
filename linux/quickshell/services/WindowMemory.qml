pragma Singleton
// Windows open where they were last time, as on Windows. Each app's windows are remembered in
// ~/.local/state/graphite/windows.json: the screen, the place on it, the size, and whether the
// window was maximised or docked into zones (Zones.qml). When a window of that app opens again,
// after a restart too, it is put back there, kept inside the screen should the screens have
// changed. Personalisation's "Remember where windows were" turns it off (rememberWindows).
//
// An app with several windows has a place for each (its "slots", oldest window first). A new
// window takes the free slot of a window that opened with the same title; the app's first
// window takes the app's first free slot whatever its title. Any other window opens as it
// would, and gets a slot of its own from then on. Browsers open their windows with the same
// title, so once their pages load, two windows that took each other's slots swap back.
//
// Hyprland says nothing of moves and resizes, so the record follows the taskbar's view of the
// windows (Taskbar.windows: refreshed every few seconds, on window events, and here when the
// mouse button is let go). A window is put back once Hyprland has opened it (the openwindow
// event): it opens centred (hyprland.lua) and moves into place, with the dispatchers docking
// uses. Some apps (kitty) then set their own size; those are put back again, twice at most.
//
// Left alone: untitled windows (X11 menus), games and Windows programs (as hyprland.lua's game
// rules), windows an app opens fullscreen (as a game or a video; maximised or not follows the
// record, as the app may be wrong about it), windows that won't keep the size
// or place they're given (splash screens, dialogs of a fixed size, apps that place their own),
// tabs, pinned windows, modal dialogs (hyprland.lua tags them "graphite-dialog"), and
// everything while windows tile. Hyprland doesn't tell which window belongs to which (its
// window list has no parents), so any other dialog is one of its app's windows: with the app
// open it takes only a slot of its own title, where it was last time. A window isn't
// moved to the workspace it was on, so a window that is asked for always opens in front.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property bool enabled: !!ShellSettings.values && ShellSettings.values.rememberWindows !== false && !ShellSettings.values.tiling

    function setEnabled(on) {
        ShellSettings.set("rememberWindows", on);
    }

    // Games and Windows programs place their own windows and pop-ups (hyprland.lua's game
    // rules), and Unity puts each of its windows where it was by itself.
    readonly property var leaveAlone: /^(steam_app_.*|.*\.exe|Minecraft.*|minecraft.*|gamescope|Unity)$/
    readonly property int slotsPerApp: 8
    readonly property int near: 4 // pixels still taken as the same place

    // { version, apps: { key: [slot] } }, key as on the taskbar (Apps.keyFor). A slot is
    // { title, last, monitor, x, y, width, height, maximised, zone, used }: title is the one
    // the window opened with, last its latest; x and y from the screen's top-left corner, and
    // the size without Hyprland's title bar (as Hyprland reports them); zone is
    // { layout, zones, count, monitor } while it is docked.
    property var record: ({ version: 1, apps: {} })
    property bool started: false

    // Open windows, by address: the slot each holds { key, index }; the zones each is docked
    // into { layout, zones, count, monitor, rect, at }; and the ones just put back, while their
    // app may still resize them { content, maximise, at, tries }.
    property var held: ({})
    property var docked: ({})
    property var settling: ({})
    property var restoredAt: ({})
    property var seen: ({}) // looked at already, to be put back or not
    property var ignored: ({}) // windows that wouldn't stay where they were put (settle())
    property var pending: [] // [{ address, tries }], new windows to look at
    property var again: [] // windows whose slots were swapped, to place again
    property bool startup: false
    property bool lookAgain: false
    property double pointerAt: 0 // when the mouse button last went down

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/graphite/windows.json"
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: saveSoon
        interval: 1500
        onTriggered: store.setText(JSON.stringify(root.record, null, 1))
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(store.text());
            if (saved && saved.apps && typeof saved.apps === "object") record = { version: 1, apps: saved.apps };
        } catch (error) {
            // nothing remembered yet, or an unreadable file
        }
        if (ShellSettings.loaded) start();
    }

    readonly property bool settingsLoaded: ShellSettings.loaded
    onSettingsLoadedChanged: if (settingsLoaded) start()

    // Turned on again: the windows open now stay where they are, and are remembered from here.
    onEnabledChanged: {
        if (!enabled || !started) return;
        for (const toplevel of Array.from(Hyprland.toplevels.values)) seen[Taskbar.addressOf(toplevel)] = true;
        snapshotSoon.restart();
    }

    // The windows open when the shell starts stay where they are (the shell was restarted),
    // unless the session has only just begun: then they are apps started with it, put back.
    function start() {
        if (started) return;
        started = true;
        startup = true;
        look();
    }

    function sessionAge() {
        const begun = Number(String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "").split("_")[1]);
        return begun ? Date.now() / 1000 - begun : Infinity;
    }

    // ---------- reading Hyprland ----------

    // The windows, their title bars (Graphite's Hyprland plugin: `hyprctl titlebars`) and the
    // screens, read together.
    Process {
        id: probe
        command: ["sh", "-c", "hyprctl -j clients; printf '\\n--\\n'; hyprctl -j titlebars 2>/dev/null; printf '\\n--\\n'; hyprctl -j monitors"]
        stdout: StdioCollector {
            onStreamFinished: root.probed(this.text)
        }
    }

    function look() {
        if (probe.running) lookAgain = true;
        else probe.running = true;
    }

    function parse(text) {
        const parts = text.split("\n--\n");
        const read = (part, fallback) => {
            try {
                return JSON.parse(part);
            } catch (error) {
                return fallback; // no title bars without the plugin
            }
        };
        return { clients: read(parts[0], null), bars: read(parts[1] || "", {}) || {}, monitors: read(parts[2] || "", null) };
    }

    function probed(text) {
        const data = parse(text);
        if (Array.isArray(data.clients) && Array.isArray(data.monitors)) handle(data);
        if (lookAgain) {
            lookAgain = false;
            look();
        }
    }

    function handle(data) {
        const clients = {};
        for (const client of data.clients) clients[client.address] = client;

        if (startup) {
            startup = false;
            const fresh = sessionAge() < 60;
            const announced = new Set(pending.map(item => item.address));
            for (const client of data.clients) {
                if (announced.has(client.address)) continue; // opened since the shell started
                if (fresh) pending.push({ address: client.address, tries: 0 });
                else seen[client.address] = true;
            }
        }

        // New windows, oldest first, so an app's windows take its slots in the order they opened.
        const waiting = [];
        const later = [];
        for (const item of pending) {
            if (clients[item.address]) waiting.push(clients[item.address]);
            else if (item.tries < 3) later.push({ address: item.address, tries: item.tries + 1 });
        }
        pending = later;
        if (later.length) restoreSoon.restart();
        waiting.sort((first, second) => age(first) - age(second));
        for (const client of waiting) restore(client, data);

        for (const address of again) {
            const hold = held[address];
            const client = clients[address];
            if (hold && client && !(pointerAt > (restoredAt[address] || 0))) put(address, record.apps[hold.key][hold.index], client, data);
        }
        again = [];

        const now = Date.now();
        for (const address of Object.keys(settling)) settle(address, clients[address], now);
        if (Object.keys(settling).length === 0) settleTimer.stop();
        snapshotSoon.restart();
    }

    function age(client) {
        return parseInt(String(client.stableId || "0"), 16) || 0;
    }

    function keyOf(client) {
        return Apps.keyFor(client.class || client.initialClass);
    }

    function eligible(client) {
        if (!client || !client.at || !client.size || !client.class) return false;
        if (!client.title && !client.initialTitle) return false;
        if (leaveAlone.test(client.class) || leaveAlone.test(client.initialClass || "")) return false;
        if (!client.floating || client.pinned) return false;
        if (client.grouped && client.grouped.length > 1) return false;
        // Modal dialogs (tagged by hyprland.lua; a tag a rule gives ends in "*" in Hyprland's list).
        if ((client.tags || []).some(tag => String(tag).replace(/\*$/, "") === "graphite-dialog")) return false;
        const workspace = client.workspace ? client.workspace.name : "";
        return !(workspace.startsWith("special:") && workspace !== Taskbar.minimizedWorkspace);
    }

    // ---------- putting windows back ----------

    function opened(address) {
        if (!started) return; // the first look, at start, takes it
        pending.push({ address: address, tries: 0 });
        restoreSoon.restart();
    }

    // Hyprland gives a new window the address of one just closed now and then, so what was
    // known of a window goes as it closes (its slot stays, with where it was).
    function closed(address) {
        for (const table of [held, docked, settling, restoredAt, seen, ignored]) delete table[address];
        pending = pending.filter(item => item.address !== address);
    }

    Timer {
        id: restoreSoon
        interval: 40
        onTriggered: root.look()
    }

    function restore(client, data) {
        const address = client.address;
        if (seen[address]) return;
        seen[address] = true;
        if (!enabled || client.fullscreen >= 2 || !eligible(client)) return;
        const key = keyOf(client);
        const index = freeSlot(key, client);
        if (index < 0) return;
        held[address] = { key: key, index: index };
        record.apps[key][index].used = Date.now();
        restoredAt[address] = Date.now();
        put(address, record.apps[key][index], client, data);
    }

    // The slot a new window of an app takes: a free one whose window opened with the same
    // title, else the first free one when the app has no other window in a slot.
    function freeSlot(key, client) {
        const slots = record.apps[key] || [];
        const taken = takenSlots(key);
        const free = slots.map((slot, index) => index).filter(index => !taken.has(index) && slots[index].width > 0);
        const title = client.initialTitle || client.title;
        const same = free.find(index => slots[index].title === title);
        if (same !== undefined) return same;
        return taken.size === 0 && free.length ? free[0] : -1;
    }

    function takenSlots(key) {
        return new Set(Object.values(held).filter(hold => hold.key === key).map(hold => hold.index));
    }

    // A monitor's usable area, from `hyprctl monitors` (as Zones.workArea).
    function areaOf(monitor) {
        return Zones.workArea({ x: monitor.x, y: monitor.y, width: monitor.width, height: monitor.height, scale: monitor.scale, lastIpcObject: { reserved: monitor.reserved } });
    }

    // Inside the area, the title bar too; never bigger than it.
    function clamp(rect, area, bar) {
        const width = Math.round(Math.max(64, Math.min(rect.width, area.width)));
        const height = Math.round(Math.max(48, Math.min(rect.height, area.height - bar)));
        return {
            x: Math.round(Math.min(Math.max(rect.x, area.x), area.x + area.width - width)),
            y: Math.round(Math.min(Math.max(rect.y, area.y + bar), area.y + area.height - height)),
            width: width,
            height: height
        };
    }

    // Puts a window where its slot says: into its zones when the layout is still the one it was
    // docked in (on the screen as it is now), else at the remembered place; then maximised if
    // it was.
    function put(address, slot, client, data) {
        if (!slot || client.fullscreen >= 2) return;
        const monitor = data.monitors.find(candidate => candidate.name === slot.monitor)
            || data.monitors.find(candidate => candidate.id === client.monitor) || data.monitors[0];
        if (!monitor) return;
        const area = areaOf(monitor);
        const bar = Number(data.bars[address]) || 0;
        const window = `window = "address:${address}"`;
        const zone = slot.zone;
        let content = null;
        if (zone && zone.layout === Zones.layoutId && zone.count === Zones.zones.length && zone.zones.length) {
            const rect = Zones.union(zone.zones.map(index => Zones.zoneRect(Zones.zones[index], area)));
            content = { x: rect.x, y: rect.y + bar, width: rect.width, height: rect.height - bar };
            docked[address] = { layout: zone.layout, zones: zone.zones.slice(), count: zone.count, monitor: monitor.name, rect: rect, at: Date.now() };
        } else {
            content = { x: monitor.x + slot.x, y: monitor.y + slot.y, width: slot.width, height: slot.height };
            delete docked[address];
        }
        content = clamp(content, area, bar);
        if (client.fullscreen === 1) Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "maximized", ${window} })`);
        apply(address, content);
        if (slot.maximised) Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "maximized", ${window} })`);
        settling[address] = { content: content, maximise: !!slot.maximised, at: Date.now(), tries: 0 };
        settleTimer.restart();
    }

    function apply(address, rect) {
        const window = `window = "address:${address}"`;
        Hyprland.dispatch(`hl.dsp.window.resize({ x = ${rect.width}, y = ${rect.height}, exact = true, ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${rect.x}, y = ${rect.y}, exact = true, ${window} })`);
    }

    // For two seconds after a window is put back: put back again if its app moved or sized it
    // (unless the mouse took it). Then the taskbar looks at it again for a tag remembered for
    // that place (window-tags.js looks at a window once, when it first sees it).
    Timer {
        id: settleTimer
        interval: 500
        repeat: true
        onTriggered: root.look()
    }

    function settle(address, client, now) {
        const state = settling[address];
        if (!client || pointerAt > state.at || now - state.at > 2000) {
            delete settling[address];
            if (client && Taskbar.tagState && Taskbar.tagState.seen) {
                Taskbar.tagState.seen.delete(address);
                Taskbar.refresh();
            }
            return;
        }
        if (now - state.at < 300 || state.maximise || client.fullscreen >= 2) return;
        const rect = state.content;
        // (kitty maximises itself again when it last closed maximised, as it believes.)
        const maximised = client.fullscreen === 1;
        const off = maximised ? Infinity : Math.abs(client.at[0] - rect.x) + Math.abs(client.at[1] - rect.y) + Math.abs(client.size[0] - rect.width) + Math.abs(client.size[1] - rect.height);
        if (off <= near) return;
        if (state.tries < 2) {
            state.tries += 1;
            if (maximised) Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "maximized", window = "address:${address}" })`);
            apply(address, rect);
            return;
        }
        // It keeps its own size or place (a splash screen or a dialog of a fixed size, or an
        // app that places its window itself): it gives the slot back and is left alone.
        delete settling[address];
        delete held[address];
        ignored[address] = true;
    }

    // A browser's windows all open as "Zen Browser" (say), so they may take each other's
    // slots. Once a page's title arrives, a window put back in the last few seconds whose title
    // is another slot's last one swaps with the window there (also just put back), or moves
    // into that slot if it is free.
    function titled(address, title) {
        const since = restoredAt[address];
        const hold = held[address];
        if (!since || !hold || Date.now() - since > 10000 || pointerAt > since) return;
        const slots = record.apps[hold.key] || [];
        if (!slots[hold.index] || slots[hold.index].last === title) return;
        const other = slots.findIndex((slot, index) => index !== hold.index && slot.last === title && slot.width > 0);
        if (other < 0) return;
        const holder = Object.keys(held).find(candidate => held[candidate].key === hold.key && held[candidate].index === other);
        if (holder && !(restoredAt[holder] && Date.now() - restoredAt[holder] < 10000 && !(pointerAt > restoredAt[holder]))) return;
        held[address] = { key: hold.key, index: other };
        again.push(address);
        if (holder) {
            held[holder] = { key: hold.key, index: hold.index };
            again.push(holder);
        }
        look();
    }

    // ---------- remembering ----------

    // Zones.qml docks a window: remembered with its zones while it stays in them.
    function dockedInto(address, zones, monitorName, rect) {
        docked[address] = { layout: Zones.layoutId, zones: zones.slice(), count: Zones.zones.length, monitor: monitorName, rect: rect, at: Date.now() };
    }

    // Whether a window fills a zone's rectangle: its title bar (when Hyprland draws one) at the
    // top of it, the rest below.
    function fills(rect, ipc) {
        return Math.abs(ipc.at[0] - rect.x) <= near && Math.abs(ipc.size[0] - rect.width) <= near
            && Math.abs(ipc.at[1] + ipc.size[1] - rect.y - rect.height) <= near
            && ipc.at[1] >= rect.y - near && ipc.at[1] <= rect.y + 48;
    }

    // The zones a window is docked into, null once it has been moved or sized out of them, or
    // undefined while it is still on its way in. A window put into a zone some other way
    // (Super + arrows, by hand, or docked before the shell started) counts as docked into the
    // zone of the layout in use that it fills.
    function zoneOf(address, ipc, monitor) {
        const dock = docked[address];
        if (dock && fills(dock.rect, ipc)) return { layout: dock.layout, zones: dock.zones, count: dock.count, monitor: dock.monitor };
        if (dock && Date.now() - dock.at < 2500) return undefined;
        delete docked[address];
        const area = Zones.workArea(monitor);
        const index = Zones.zones.findIndex(zone => fills(Zones.zoneRect(zone, area), ipc));
        return index < 0 ? null : { layout: Zones.layoutId, zones: [index], count: Zones.zones.length, monitor: monitor.name };
    }

    Timer {
        id: snapshotSoon
        interval: 250
        onTriggered: root.snapshot()
    }

    function snapshot() {
        if (!started || !enabled) return;
        const now = Date.now();
        const monitors = {};
        for (const monitor of Array.from(Hyprland.monitors.values)) monitors[monitor.id] = monitor;
        const open = new Set();
        const windows = [];
        for (const toplevel of Array.from(Hyprland.toplevels.values)) {
            const address = Taskbar.addressOf(toplevel);
            open.add(address);
            const ipc = toplevel.lastIpcObject;
            if (!ipc || !ipc.address) continue;
            const monitor = monitors[ipc.monitor];
            // Not windows not yet looked at for putting back, nor any on a stand-in screen (as
            // while the screens go off when signing out).
            if (!seen[address] || ignored[address] || !monitor || /^(FALLBACK|HEADLESS)/.test(monitor.name) || !eligible(ipc)) continue;
            windows.push({ address: address, ipc: ipc, monitor: monitor });
        }
        for (const table of [held, docked, settling, restoredAt, seen, ignored]) {
            for (const address of Object.keys(table)) if (!open.has(address)) delete table[address];
        }

        let changed = false;
        // Windows without a slot yet: one whose window opened with the same title, else a new
        // one (the least used free one when the app has all it may keep).
        windows.sort((first, second) => age(first.ipc) - age(second.ipc));
        for (const window of windows) {
            if (held[window.address]) continue;
            const key = keyOf(window.ipc);
            const slots = record.apps[key] || (record.apps[key] = []);
            const taken = takenSlots(key);
            const title = window.ipc.initialTitle || window.ipc.title;
            let index = slots.findIndex((slot, candidate) => !taken.has(candidate) && slot.title === title);
            if (index < 0 && slots.length < slotsPerApp) {
                index = slots.length;
                slots.push({});
            } else if (index < 0) {
                const free = slots.map((slot, candidate) => candidate).filter(candidate => !taken.has(candidate));
                if (!free.length) continue;
                index = free.sort((first, second) => (slots[first].used || 0) - (slots[second].used || 0))[0];
                slots[index] = {};
            }
            slots[index].used = now;
            held[window.address] = { key: key, index: index };
            changed = true;
        }

        for (const window of windows) {
            const hold = held[window.address];
            const slots = hold && record.apps[hold.key];
            if (!slots || !slots[hold.index] || settling[window.address]) continue;
            const ipc = window.ipc;
            const slot = slots[hold.index];
            const next = Object.assign({}, slot, { title: ipc.initialTitle || ipc.title || "" });
            // The title stays the one put back with for a few seconds (titled() above).
            if (!restoredAt[window.address] || now - restoredAt[window.address] > 10000) next.last = ipc.title || "";
            if (ipc.fullscreen === 1) {
                next.maximised = true;
            } else if (!ipc.fullscreen) {
                const zone = zoneOf(window.address, ipc, window.monitor);
                if (zone === undefined) continue;
                Object.assign(next, {
                    monitor: window.monitor.name,
                    x: ipc.at[0] - window.monitor.x,
                    y: ipc.at[1] - window.monitor.y,
                    width: ipc.size[0],
                    height: ipc.size[1],
                    maximised: false,
                    zone: zone
                });
            }
            // (Fullscreen, as a video or a game, isn't remembered: the slot stays as it was.)
            if (JSON.stringify(next) !== JSON.stringify(slot)) {
                slots[hold.index] = next;
                changed = true;
            }
        }
        if (changed) saveSoon.restart();
    }

    // Kept up with the taskbar's view of the windows (it changes whenever one moves, opens,
    // closes, or is maximised); and the end of a drag is looked at straight away.
    readonly property var taskbarWindows: Taskbar.windows
    onTaskbarWindowsChanged: snapshotSoon.restart()

    Connections {
        target: Zones
        function onPointerDownChanged() {
            if (Zones.pointerDown) root.pointerAt = Date.now();
            else Taskbar.refresh();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                root.opened(Taskbar.addressOf({ address: event.data.split(",")[0] }));
            } else if (event.name === "closewindow") {
                root.closed(Taskbar.addressOf({ address: event.data }));
            } else if (event.name === "windowtitlev2") {
                const comma = event.data.indexOf(",");
                root.titled(Taskbar.addressOf({ address: event.data.slice(0, comma) }), event.data.slice(comma + 1));
            }
        }
    }

    // `qs -c graphite ipc call windows state` shows what is remembered and which slot each open
    // window holds; `forget` starts again from the windows as they are now, and `forgetApp KEY`
    // does so for one app. `dock ADDRESS ZONE` docks a window into a zone of the layout in use
    // without a drag, as a Shift + drag does (for trying it from a terminal).
    IpcHandler {
        target: "windows"

        function state(): string {
            return JSON.stringify({ enabled: root.enabled, held: root.held, docked: root.docked, settling: Object.keys(root.settling), apps: root.record.apps }, null, 1);
        }

        function forget(): void {
            root.record = { version: 1, apps: {} };
            root.held = {};
            root.docked = {};
            root.snapshot();
            saveSoon.restart();
        }

        function forgetApp(key: string): void {
            delete root.record.apps[key];
            for (const address of Object.keys(root.held)) if (root.held[address].key === key) delete root.held[address];
            root.snapshot();
            saveSoon.restart();
        }

        function dock(address: string, zone: int): void {
            const toplevel = Taskbar.toplevelFor(Taskbar.addressOf({ address: address }));
            if (!toplevel || !toplevel.monitor || zone < 0 || zone >= Zones.zones.length) return;
            const rect = Zones.zoneRect(Zones.zones[zone], Zones.workArea(toplevel.monitor));
            root.dockedInto(Taskbar.addressOf(toplevel), [zone], toplevel.monitor.name, rect);
            Zones.snap(Taskbar.addressOf(toplevel), rect);
        }
    }
}
