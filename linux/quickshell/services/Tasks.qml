pragma Singleton
// The task manager's numbers (system/task-sample.sh, every two seconds while it is open):
// how busy the processor is, memory in use, disk and network speed (with a minute of history
// for the graphs), and what is running: "Apps" are the programs with a window (each with all
// the processes it started, found through their parents), "Background" everything else of
// the person's. Ending a task asks its windows to close first, then stops its processes, and
// forces them only if they are still there a few seconds later.

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
    property var history: ({ cpu: [], memory: [], disk: [], net: [] }) // the last 30 samples, 0 to 1

    // [{ key, name, icon, pids, cpu, memory, windows, app }]
    property var apps: []
    property var background: []

    property var previous: null // the last sample's running totals and time

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
        const processes = [];
        let disk = [0, 0];
        let net = [0, 0];
        for (const line of text.split("\n")) {
            const parts = line.split(" ");
            if (parts[0] === "CPU") cpu = Number(parts[1]) / 100;
            else if (parts[0] === "MEM") {
                memoryTotal = Number(parts[1]);
                memoryUsed = Number(parts[1]) - Number(parts[2]);
            } else if (parts[0] === "DISK") disk = [Number(parts[1]) * 512, Number(parts[2]) * 512];
            else if (parts[0] === "NET") net = [Number(parts[1]), Number(parts[2])];
            else if (parts[0] === "P") processes.push({ pid: Number(parts[1]), ppid: Number(parts[2]), user: parts[3], cpu: Number(parts[4]), memory: Number(parts[5]), name: parts.slice(6).join(" ") });
        }

        const now = Date.now() / 1000;
        if (previous) {
            const seconds = Math.max(0.5, now - previous.time);
            diskRead = Math.max(0, (disk[0] - previous.disk[0]) / seconds);
            diskWrite = Math.max(0, (disk[1] - previous.disk[1]) / seconds);
            netDown = Math.max(0, (net[0] - previous.net[0]) / seconds);
            netUp = Math.max(0, (net[1] - previous.net[1]) / seconds);
        }
        previous = { time: now, disk: disk, net: net };

        const push = (list, value) => list.concat([Math.max(0, Math.min(1, value))]).slice(-30);
        history = {
            cpu: push(history.cpu, cpu),
            memory: push(history.memory, memoryUsed / Math.max(1, memoryTotal)),
            disk: push(history.disk, (diskRead + diskWrite) / (100 * 1024 * 1024)),
            net: push(history.net, (netDown + netUp) / (12.5 * 1024 * 1024))
        };

        group(processes);
    }

    // Each window's process and everything below it make one app; the rest are background.
    function group(processes) {
        const byPid = {};
        const children = {};
        for (const process of processes) {
            byPid[process.pid] = process;
            (children[process.ppid] = children[process.ppid] || []).push(process.pid);
        }
        const taken = {};
        // The shell itself (its windows: this one, the Control Panel) and what it runs (this
        // sampler) are the desktop, not tasks.
        const shell = processes.filter(process => process.name === "qs" || process.name === "quickshell");
        const queue = shell.map(process => process.pid);
        while (queue.length) {
            const pid = queue.shift();
            if (taken[pid]) continue;
            taken[pid] = true;
            for (const child of children[pid] || []) queue.push(child);
        }
        const found = {};
        for (const window of windows) {
            if (taken[window.pid]) continue;
            const key = window.class || window.initialClass || String(window.pid);
            const app = found[key] || { key: key, name: appName(key, window.title), icon: key, pids: [], cpu: 0, memory: 0, windows: [], app: true };
            app.windows.push(window.address);
            const queue = [window.pid];
            while (queue.length) {
                const pid = queue.shift();
                if (taken[pid] || !byPid[pid]) continue;
                taken[pid] = true;
                app.pids.push(pid);
                app.cpu += byPid[pid].cpu;
                app.memory += byPid[pid].memory;
                for (const child of children[pid] || []) queue.push(child);
            }
            found[key] = app;
        }
        apps = Object.values(found).sort((first, second) => first.name.localeCompare(second.name));
        background = processes
            .filter(process => !taken[process.pid] && process.user === user && process.name !== "top" && process.name !== "task-sample.sh")
            .map(process => ({ key: String(process.pid), name: process.name, icon: "", pids: [process.pid], cpu: process.cpu, memory: process.memory, windows: [], app: false }))
            .sort((first, second) => (second.cpu - first.cpu) || (second.memory - first.memory))
            .slice(0, 60);
    }

    function appName(windowClass, title) {
        const entry = DesktopEntries.heuristicLookup(windowClass);
        return entry ? entry.name : (windowClass || title);
    }

    // The desktop itself is never offered for ending.
    readonly property var protectedNames: ["Hyprland", "qs", "quickshell", "systemd", "dbus-broker", "dbus-daemon", "pipewire", "wireplumber", "greetd", "hyprpolkitagen", "hypridle"]

    function canEnd(task) {
        return task.app || !protectedNames.includes(task.name);
    }

    function end(task) {
        if (!canEnd(task)) return;
        for (const address of task.windows) Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`);
        const pids = task.pids.join(" ");
        Quickshell.execDetached(["sh", "-c", `sleep ${task.windows.length ? 2 : 0}; kill ${pids} 2>/dev/null; sleep 4; kill -9 ${pids} 2>/dev/null`]);
    }

    function size(kilobytes) {
        return kilobytes >= 1048576 ? (kilobytes / 1048576).toFixed(1) + " GB" : Math.round(kilobytes / 1024) + " MB";
    }

    function speed(bytes) {
        return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB/s" : bytes >= 1024 ? Math.round(bytes / 1024) + " KB/s" : Math.round(bytes) + " B/s";
    }
}
