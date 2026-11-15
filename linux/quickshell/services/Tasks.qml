pragma Singleton
// The task manager's numbers (system/task-sample.sh, every two seconds while it is open):
// how busy the processor, disks and graphics card are, memory in use, disk and network speed
// (with a minute of history for the graphs), and what is running: "Apps" are the programs with a window (each with all
// the processes it started, found through their parents, which open beneath it), "Background"
// everything else of the person's, and "Desktop" what makes the desktop itself: Graphite
// (the shell and its helpers, such as the wrapper each app is started through, in one entry)
// and the parts that are never ended. Ending a task asks its windows to close first, then stops
// its processes, and forces them only if they are still there a few seconds later.
//
// The startup apps are here too, as on Windows' Startup tab: system/autostart.sh's entries in
// ~/.config/autostart (the Control Panel's Apps page adds them), on unless Hidden=true.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property bool watching: false

    property real cpu: 0
    property real memoryTotal: 0      // kB
    property real memoryUsed: 0       // kB
    property real diskRead: 0         // bytes a second
    property real diskWrite: 0
    property real netDown: 0
    property real netUp: 0
    property real diskBusy: 0         // the busiest disk's active time, 0 to 1
    property int cores: 1
    property real speedMhz: 0
    property real uptime: 0           // seconds
    property int threads: 0
    property int processCount: 0
    property var link: ({ name: "", kind: "", mbits: 0 })   // the network adapter to the internet
    property var gpu: null            // { name, busy (0 to 1), memoryUsed, memoryTotal (MiB), temperature }
    property var history: ({ cpu: [], memory: [], disk: [], net: [], gpu: [] }) // the last 40 samples, 0 to 1

    // The network's use of its link, when the adapter says how fast it is (Wi-Fi often doesn't).
    readonly property real netBusy: link.mbits > 0 ? (netDown + netUp) * 8 / (link.mbits * 1000000) : 0

    // [{ key, name, icon, pids, cpu, memory, disk, windows, app, desk, command, processes }]
    // (disk in bytes a second; processes: [{ key, pid, name, command, cpu, memory, disk }],
    // what an entry gathers, which the task manager opens beneath it)
    property var apps: []
    property var background: []
    property var desktop: []

    property var previous: null   // the last sample's running totals and time ({ time, disk, net, busy })
    property var previousIo: ({}) // pid -> bytes read and written, at the last sample
    property var children: ({})   // pid -> its children's pids, at the last sample

    readonly property string user: Quickshell.env("USER") || ""

    Timer {
        interval: 2000
        repeat: true
        running: root.watching
        triggeredOnStart: true
        onTriggered: if (!sampler.running) sampler.running = true
    }

    Process {
        id: sampler
        command: ["bash", Quickshell.shellDir + "/../system/task-sample.sh"]
        stdout: StdioCollector { onStreamFinished: root.read(this.text) }
    }

    Process {
        id: windowReader
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(this.text).filter(window => window.pid > 0);
                } catch (error) {
                    root.windows = [];
                }
            }
        }
    }
    property var windows: []

    function read(text) {
        windowReader.running = true;
        const now = Date.now() / 1000;
        const seconds = previous ? Math.max(0.5, now - previous.time) : 1;
        const processes = [];
        const io = {};
        let disk = [0, 0];
        let net = [0, 0];
        let busy = {};
        let card = null;
        const lines = text.split("\n");
        // The core count first: a process's share is of the whole processor, as on Windows.
        const coreLine = lines.find(line => line.startsWith("CORES "));
        if (coreLine) {
            cores = Math.max(1, Number(coreLine.split(" ")[1]) || 1);
            speedMhz = Number(coreLine.split(" ")[2]) || 0;
        }
        for (const line of lines) {
            if (line.startsWith("GPU\t")) {
                const parts = line.split("\t");
                card = { busy: (Number(parts[1]) || 0) / 100, memoryUsed: Number(parts[2]) || 0, memoryTotal: Number(parts[3]) || 0, temperature: Number(parts[4]) || 0, name: parts[5] || "" };
                continue;
            }
            if (line.startsWith("P\t")) {
                const parts = line.split("\t");
                const pid = Number(parts[1]);
                const read = Number(parts[6]) || 0;
                const written = Number(parts[7]) || 0;
                const before = previousIo[pid];
                io[pid] = [read, written];
                processes.push({
                    pid: pid,
                    ppid: Number(parts[2]) || 0,
                    user: parts[3],
                    cpu: (Number(parts[4]) || 0) / cores,
                    memory: Number(parts[5]) || 0,
                    disk: before ? Math.max(0, (read - before[0] + written - before[1]) / seconds) : 0,
                    name: fullName(parts[8] || "", parts[9] || ""),
                    command: parts[9] || ""
                });
                continue;
            }
            const parts = line.split(" ");
            if (parts[0] === "CPU") cpu = Number(parts[1]) / 100;
            else if (parts[0] === "MEM") {
                memoryTotal = Number(parts[1]);
                memoryUsed = Number(parts[1]) - Number(parts[2]);
            } else if (parts[0] === "DISK") disk = [Number(parts[1]) * 512, Number(parts[2]) * 512];
            else if (parts[0] === "NET") net = [Number(parts[1]), Number(parts[2])];
            else if (parts[0] === "DISKS") for (let index = 1; index + 1 < parts.length; index += 2) busy[parts[index]] = Number(parts[index + 1]) || 0;
            else if (parts[0] === "LINK") link = { name: parts[1], kind: parts[2], mbits: Number(parts[3]) || 0 };
            else if (parts[0] === "UPTIME") {
                uptime = Number(parts[1]) || 0;
                threads = Number(parts[2]) || 0;
            }
        }
        previousIo = io;
        gpu = card;

        if (previous) {
            // Each disk's busy milliseconds since; the busiest is the disk's figure.
            diskBusy = Math.min(1, Math.max(0, ...Object.keys(busy).map(name => (busy[name] - (previous.busy[name] || busy[name])) / (seconds * 1000))));
            diskRead = Math.max(0, (disk[0] - previous.disk[0]) / seconds);
            diskWrite = Math.max(0, (disk[1] - previous.disk[1]) / seconds);
            netDown = Math.max(0, (net[0] - previous.net[0]) / seconds);
            netUp = Math.max(0, (net[1] - previous.net[1]) / seconds);
        }
        previous = { time: now, disk: disk, net: net, busy: busy };

        const push = (list, value) => list.concat([Math.max(0, Math.min(1, value))]).slice(-40);
        history = {
            cpu: push(history.cpu, cpu),
            memory: push(history.memory, memoryUsed / Math.max(1, memoryTotal)),
            disk: push(history.disk, diskBusy),
            net: push(history.net, link.mbits > 0 ? netBusy : (netDown + netUp) / (12.5 * 1024 * 1024)),
            gpu: push(history.gpu, card ? card.busy : 0)
        };

        group(processes);
    }

    // A program's whole name: top cuts them at 15 letters ("at-spi-bus-laun"), the command line
    // has it ("/usr/lib/at-spi-bus-launcher").
    function fullName(name, command) {
        if (name.length < 15) return name;
        const program = command.split(" ")[0].split("/").pop();
        return program.startsWith(name) ? program : name;
    }

    // What Graphite runs from its own folder (the wrapper each app is started through, the
    // update checks, warm.sh): the desktop's, not tasks of their own.
    readonly property var deskPaths: ["/.config/quickshell/graphite/", "/opt/graphite-desk/", "qs -c graphite"]

    function isDesk(process) {
        return process.name === "qs" || process.name === "quickshell" || deskPaths.some(path => process.command.includes(path));
    }

    // A process as one row beneath its entry.
    function row(process) {
        return { key: "pid:" + process.pid, pid: process.pid, name: process.name, command: process.command, cpu: process.cpu, memory: process.memory, disk: process.disk };
    }

    // Everything under some processes, each taken once: an entry's processes.
    function gather(entry, starts, byPid, taken) {
        const queue = starts.slice();
        while (queue.length) {
            const pid = queue.shift();
            if (taken[pid] || !byPid[pid]) continue;
            taken[pid] = true;
            const process = byPid[pid];
            entry.pids.push(pid);
            entry.processes.push(row(process));
            entry.cpu += process.cpu;
            entry.memory += process.memory;
            entry.disk += process.disk;
            for (const child of children[pid] || []) queue.push(child);
        }
        entry.processes.sort((first, second) => second.cpu - first.cpu || second.memory - first.memory);
        return entry;
    }

    // Each window's process and everything below it make one app; the shell and its helpers
    // make Graphite; the rest are background, or the desktop's own parts.
    function group(processes) {
        const byPid = {};
        const tree = {};
        for (const process of processes) {
            byPid[process.pid] = process;
            (tree[process.ppid] = tree[process.ppid] || []).push(process.pid);
        }
        children = tree;
        processCount = processes.length;
        const taken = {};
        // The sampler and what it runs aren't tasks.
        const sampling = processes.filter(process => process.command.includes("task-sample.sh")).map(process => process.pid);
        while (sampling.length) {
            const pid = sampling.shift();
            if (taken[pid]) continue;
            taken[pid] = true;
            for (const child of tree[pid] || []) sampling.push(child);
        }

        const found = {};
        for (const window of windows) {
            // The shell's own windows (this one, the Control Panel) are Graphite's.
            if (taken[window.pid] || (byPid[window.pid] && isDesk(byPid[window.pid]))) continue;
            const key = window.class || window.initialClass || String(window.pid);
            const app = found[key] || { key: key, name: appName(key, window.title), icon: key, pids: [], cpu: 0, memory: 0, disk: 0, windows: [], app: true, desk: false, command: "", processes: [] };
            app.windows.push(window.address);
            if (!app.command && byPid[window.pid]) app.command = byPid[window.pid].command;
            found[key] = gather(app, [window.pid], byPid, taken);
        }
        apps = Object.values(found).filter(app => app.pids.length > 0).sort((first, second) => first.name.localeCompare(second.name));

        // The wrapper an app was started through (system/launch.sh) and what it started besides
        // the app's window (Steam's own launcher and runtime, for one) are the app's.
        const owners = {};
        for (const app of Object.values(found)) for (const pid of app.pids) owners[pid] = app;
        for (const process of processes) {
            if (taken[process.pid] || !process.command.includes("/system/launch.sh")) continue;
            const queue = [process.pid];
            const seen = {};
            let owner = null;
            while (queue.length && !owner) {
                const pid = queue.shift();
                if (seen[pid]) continue;
                seen[pid] = true;
                owner = owners[pid] || null;
                for (const child of tree[pid] || []) queue.push(child);
            }
            if (owner) gather(owner, [process.pid], byPid, taken);
        }

        // Then the shell with everything it runs, and its helpers by themselves: a wrapper whose
        // app has no window is Graphite's, not what it started.
        const desk = { key: "graphite", name: "Graphite", icon: "user-desktop", pids: [], cpu: 0, memory: 0, disk: 0, windows: [], app: false, desk: true, command: "", processes: [] };
        gather(desk, processes.filter(process => process.name === "qs" || process.name === "quickshell").map(process => process.pid), byPid, taken);
        for (const process of processes.filter(process => !taken[process.pid] && isDesk(process))) {
            taken[process.pid] = true;
            desk.pids.push(process.pid);
            desk.processes.push(row(process));
            desk.cpu += process.cpu;
            desk.memory += process.memory;
            desk.disk += process.disk;
        }

        const single = process => Object.assign(row(process), { key: String(process.pid), icon: "", pids: [process.pid], windows: [], app: false, desk: false, processes: [] });
        // Not the ones that have finished and wait to be collected ("<defunct>").
        const rest = processes.filter(process => !taken[process.pid] && process.user === user && !process.command.endsWith("<defunct>"));
        background = rest.filter(process => !protectedNames.includes(process.name)).map(single);
        desktop = (desk.pids.length ? [desk] : []).concat(rest.filter(process => protectedNames.includes(process.name)).map(single));
    }

    function appName(windowClass, title) {
        const entry = DesktopEntries.heuristicLookup(windowClass);
        return entry ? entry.name : (windowClass || title);
    }

    // The desktop itself is never offered for ending.
    readonly property var protectedNames: ["Hyprland", "qs", "quickshell", "systemd", "dbus-broker", "dbus-daemon", "pipewire", "pipewire-pulse", "wireplumber", "greetd", "hyprpolkitagen", "hypridle", "xdg-desktop-por", "Xwayland"]

    function canEnd(task) {
        return !!task && !task.desk && (task.app || !protectedNames.includes(task.name));
    }

    function end(task) {
        if (!canEnd(task)) return;
        stop(task.windows, task.pids);
    }

    // The task and everything it started since, as Windows' "End process tree".
    function endTree(task) {
        if (!canEnd(task)) return;
        const pids = [];
        const queue = task.pids.slice();
        while (queue.length) {
            const pid = queue.shift();
            if (pids.includes(pid)) continue;
            pids.push(pid);
            for (const child of children[pid] || []) queue.push(child);
        }
        stop(task.windows, pids);
    }

    function stop(windows, pids) {
        for (const address of windows) Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`);
        const list = pids.join(" ");
        Quickshell.execDetached(["sh", "-c", `sleep ${windows.length ? 2 : 0}; kill ${list} 2>/dev/null; sleep 4; kill -9 ${list} 2>/dev/null`]);
    }

    // Files, at the program a process runs: selected in its folder. A Flatpak app's program is
    // inside its own folder (the sandbox's /app), which opens instead when the program can't be read.
    function openLocation(pid) {
        Quickshell.execDetached(["sh", "-c", [
            'exe="$(readlink "/proc/$1/exe" 2>/dev/null)"',
            'app="$(sed -n "s/^app-path=//p" "/proc/$1/root/.flatpak-info" 2>/dev/null)"',
            'if [ -n "$app" ]; then case "$exe" in /app/*) exe="$app${exe#/app}" ;; *) exe="" ;; esac; fi',
            'if [ -n "$exe" ] && [ -e "$exe" ]; then exec nautilus --select "$exe"; fi',
            'if [ -n "$app" ]; then exec nautilus --new-window "$app"; fi',
            'notify-send -a "Graphite" -i dialog-information "Can\'t find where it is" "Its program can\'t be read: it may belong to the system."'
        ].join("\n"), "sh", String(pid)]);
    }

    function searchOnline(name) {
        Quickshell.execDetached(["xdg-open", "https://www.google.com/search?q=" + encodeURIComponent(name + " process Linux")]);
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", String(text)]);
    }

    // ---------- startup apps ----------

    // [{ id, name, icon, on }], every entry in ~/.config/autostart.
    property var startup: []

    function readStartup() {
        startupReader.running = true;
    }

    Process {
        id: startupReader
        command: ["sh", "-c", 'for f in "$HOME/.config/autostart"/*.desktop; do [ -f "$f" ] || continue; '
            + 'printf "%s\\t%s\\t%s\\t%s\\n" "$(basename "$f" .desktop)" "$(sed -n "s/^Name=//p" "$f" | head -1)" "$(sed -n "s/^Icon=//p" "$f" | head -1)" "$(grep -qi "^Hidden=true" "$f" && echo off || echo on)"; done']
        stdout: StdioCollector {
            onStreamFinished: root.startup = this.text.split("\n").filter(line => line).map(line => {
                const parts = line.split("\t");
                const entry = DesktopEntries.byId(parts[0]);
                return { id: parts[0], name: (entry && entry.name) || parts[1] || parts[0], icon: (entry && entry.icon) || parts[2] || parts[0], on: parts[3] === "on" };
            }).sort((first, second) => first.name.localeCompare(second.name))
        }
    }

    // Off is Hidden=true in its [Desktop Entry] (autostart.sh skips those), as the
    // specification has it; on takes that away again.
    function setStartup(id, on) {
        const file = Quickshell.env("HOME") + "/.config/autostart/" + String(id).replace(/[\/]/g, "") + ".desktop";
        const change = on ? "sed -i '/^Hidden=/Id' \"$1\"" : "sed -i '/^Hidden=/Id' \"$1\" && sed -i '0,/^\\[Desktop Entry\\]/s//&\\nHidden=true/' \"$1\"";
        startupWriter.command = ["sh", "-c", change, "sh", file];
        startupWriter.running = true;
    }

    Process {
        id: startupWriter
        onExited: root.readStartup()
    }

    function size(kilobytes) {
        kilobytes = Number(kilobytes) || 0;
        return kilobytes >= 1048576 ? (kilobytes / 1048576).toFixed(1) + " GB" : Math.round(kilobytes / 1024) + " MB";
    }

    function speed(bytes) {
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB/s" : bytes >= 1024 ? Math.round(bytes / 1024) + " KB/s" : Math.round(bytes) + " B/s";
    }
}
