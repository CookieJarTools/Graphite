pragma Singleton
// Drives for the Control Panel: every disk and USB stick with its partitions (lsblk), how full
// each is, and which drive the system runs from (never offered for formatting). Mounting and
// ejecting go through udisks, as Files does; formatting and erasing through graphite-admin.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ path, model, size, removable, system, parts: [{ path, label, fs, size, used, mount }] }]
    property var disks: []
    property bool busy: false
    property string message: ""

    function refresh() {
        reader.running = true;
    }

    Process {
        id: reader
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,RM,HOTPLUG,TRAN,FSUSED"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devices = JSON.parse(this.text).blockdevices || [];
                    root.disks = devices.filter(device => device.type === "disk" && !/^(zram|loop)/.test(device.name)).map(root.disk);
                } catch (error) {
                    root.disks = [];
                }
            }
        }
    }

    function mounts(device) {
        return (device.mountpoints || []).filter(point => point);
    }

    // Everything mounted on or under a device (through encryption), for "is this the system?".
    function allMounts(device) {
        return mounts(device).concat(...(device.children || []).map(child => allMounts(child)));
    }

    function disk(device) {
        const parts = (device.children || []).filter(child => child.type === "part").map(part => {
            // An encrypted partition: what it holds, once unlocked.
            const inner = (part.children || [])[0];
            const shown = inner && mounts(inner).length ? inner : part;
            const mount = mounts(shown)[0] || "";
            const named = ({ "/": "System", "/boot": "Start-up files", "/home": "Your files" })[mount];
            return {
                path: part.path,
                name: named || part.label || (inner && inner.label) || "",
                label: part.label || (inner && inner.label) || "",
                fs: part.fstype === "crypto_LUKS" ? "encrypted" : (part.fstype || ""),
                size: Number(part.size),
                used: Number(shown.fsused || 0),
                mount: mounts(shown)[0] || ""
            };
        });
        const everything = allMounts(device);
        return {
            path: device.path,
            model: (device.model || "").trim() || (device.tran === "usb" ? "USB drive" : "Drive"),
            size: Number(device.size),
            removable: device.rm === true || device.rm === "1" || device.hotplug === true || device.hotplug === "1" || device.tran === "usb",
            system: everything.includes("/") || everything.includes("/boot"),
            parts: parts
        };
    }

    function size(bytes) {
        return Machine.size(bytes);
    }

    function mount(path) {
        run(["udisksctl", "mount", "-b", path, "--no-user-interaction"], "", ["udisksctl", "mount", "-b", path]);
    }

    function unmount(path) {
        run(["udisksctl", "unmount", "-b", path], "Safe to remove");
    }

    function eject(disk) {
        const parts = disk.parts.filter(part => part.mount).map(part => `udisksctl unmount -b ${part.path} >/dev/null &&`).join(" ");
        run(["sh", "-c", `${parts} udisksctl power-off -b ${disk.path}`], "You can take it out now");
    }

    function open(mount) {
        Quickshell.execDetached(["xdg-open", mount]);
    }

    function format(path, fs, label) {
        run(["pkexec", "/usr/local/lib/graphite/graphite-admin", "format", path, fs, label], "Formatted");
    }

    function erase(path, fs, label) {
        run(["pkexec", "/usr/local/lib/graphite/graphite-admin", "erase", path, fs, label], "Erased");
    }

    // A command, with what to say when it worked; `retry` runs if the first needs a password
    // (udisks without asking first, then with the password prompt).
    function run(command, done, retry) {
        busy = true;
        message = "";
        runner.done = done || "";
        runner.retry = retry || null;
        runner.command = command;
        runner.running = true;
    }

    Process {
        id: runner
        property string done
        property var retry
        stderr: StdioCollector { id: runnerError }
        onExited: code => {
            if (code !== 0 && retry) {
                const again = retry;
                retry = null;
                command = again;
                running = true;
                return;
            }
            root.busy = false;
            root.message = code === 0 ? done : code === 126 || code === 127 ? "" : (runnerError.text.trim().split("\n").pop() || "That didn't work").replace(/^Error [^:]*: /, "");
            root.refresh();
        }
    }

    // Plugged in or out: the list follows within a few seconds while the page is open.
    property bool watching: false
    Timer {
        interval: 3000
        repeat: true
        running: root.watching
        triggeredOnStart: true
        onTriggered: if (!reader.running) reader.running = true
    }
}
