pragma Singleton
// Drives for the Control Panel: every disk and USB stick with its partitions (lsblk), how full
// each is, and which drive the system runs from (never offered for formatting). Mounting and
// ejecting go through udisks, as Files does; formatting and erasing through graphite-admin.
// A Windows dynamic disk (Windows' own layout, which Linux doesn't read by itself) shows its
// volumes once they're opened (graphite-admin dynamic-disks, with Arch's ldmtool).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ path, model, size, removable, system, dynamic, parts: [{ path, label, fs, size, used, mount, volume }] }]
    // (dynamic: a Windows dynamic disk; its parts are its volumes, none until opened)
    property var disks: []
    property bool busy: false
    property string message: ""

    function refresh() {
        reader.running = true;
    }

    Process {
        id: reader
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,RM,HOTPLUG,TRAN,FSUSED,PARTTYPE"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devices = JSON.parse(this.text).blockdevices || [];
                    // Only a real change reaches the page, which rebuilds its rows from this.
                    const disks = devices.filter(device => device.type === "disk" && !/^(zram|loop)/.test(device.name)).map(root.disk);
                    if (JSON.stringify(disks) !== JSON.stringify(root.disks)) root.disks = disks;
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

    // The partition type holding a Windows dynamic disk's volumes (its "LDM data").
    readonly property string dynamicData: "af9b60a0-1431-4f62-bc68-3311714a69ad"

    // Space used, to 100 MB: as the page shows it, and the system drive's changes every few
    // seconds otherwise.
    function roughly(bytes) {
        return Math.round(Number(bytes || 0) / 1e8) * 1e8;
    }

    function disk(device) {
        const partitions = (device.children || []).filter(child => child.type === "part");
        const dynamic = partitions.some(part => (part.parttype || "").toLowerCase() === dynamicData);
        if (dynamic) {
            // Its volumes, each a device of its own once opened, on the drive itself (or its data part).
            const isVolume = child => child.type === "ldm" || child.type === "dm";
            const volumes = (device.children || []).filter(isVolume).concat(...partitions
                .filter(part => (part.parttype || "").toLowerCase() === dynamicData)
                .map(part => (part.children || []).filter(isVolume)));
            return {
                path: device.path,
                model: (device.model || "").trim() || "Drive",
                size: Number(device.size),
                removable: false,
                system: false,
                dynamic: true,
                parts: volumes.map(volume => ({
                    path: volume.path,
                    name: volume.label || "Windows volume",
                    label: volume.label || "",
                    fs: volume.fstype || "",
                    size: Number(volume.size),
                    used: roughly(volume.fsused),
                    mount: mounts(volume)[0] || "",
                    volume: true
                }))
            };
        }
        const parts = partitions.map(part => {
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
                used: roughly(shown.fsused),
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
            dynamic: false,
            parts: parts
        };
    }

    function size(bytes) {
        return Machine.size(bytes);
    }

    function mount(path) {
        runner.mounting = path;
        run(["udisksctl", "mount", "-b", path, "--no-user-interaction"], "", ["udisksctl", "mount", "-b", path]);
    }

    // Windows partitions Windows left marked in use (Fast Startup, or a shutdown that didn't
    // finish), which Linux connects only to read: { path: true }, found from the kernel's
    // word when connecting failed.
    property var inUse: ({})

    function mountReadOnly(path) {
        run(["udisksctl", "mount", "-b", path, "-o", "ro", "--no-user-interaction"], "Connected to read only", ["udisksctl", "mount", "-b", path, "-o", "ro"]);
    }

    // The mark cleared (graphite-admin ntfs-repair), then connected.
    function repair(path) {
        runner.mounting = path;
        run(["sh", "-c", `${Updates.partsFirst}; pkexec /usr/local/lib/graphite/graphite-admin ntfs-repair "$1" || exit 1; udisksctl mount -b "$1" --no-user-interaction >/dev/null 2>&1 || udisksctl mount -b "$1" >/dev/null`, "sh", path],
            "Repaired and connected. Windows checks the drive the next time it starts.");
    }

    Process {
        id: inUseCheck
        property string path
        // Only what the kernel said since this try began: an older refusal may be repaired since.
        property real since
        command: ["sh", "-c", `journalctl -k --since "@$2" --no-pager 2>/dev/null | grep -q "ntfs3($(basename "$1")): volume is dirty"`, "sh", path, String(Math.floor(since / 1000))]
        onExited: code => {
            if (code !== 0) return;
            root.inUse = Object.assign({}, root.inUse, { [path]: true });
            root.message = "";
        }
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

    // A Windows dynamic disk's volumes, opened (and at every start from now on), with the
    // system parts that know how put in place first if need be.
    function openDynamic() {
        run(["sh", "-c", `${Updates.partsFirst}; pkexec /usr/local/lib/graphite/graphite-admin dynamic-disks`],
            "Opened: connect a volume to see its files");
    }

    // A Windows dynamic disk made a basic one, its files kept (graphite-admin dynamic-to-basic),
    // its volume disconnected first.
    function convertDynamic(disk) {
        const disconnect = disk.parts.filter(part => part.mount).map(part => `udisksctl unmount -b ${part.path} >/dev/null || exit 1; `).join("");
        run(["sh", "-c", `${disconnect}${Updates.partsFirst}; pkexec /usr/local/lib/graphite/graphite-admin dynamic-to-basic "$1"`, "sh", disk.path],
            "Converted: it's a basic disk now, on Linux and Windows");
    }

    function erase(path, fs, label) {
        run(["pkexec", "/usr/local/lib/graphite/graphite-admin", "erase", path, fs, label], "Erased");
    }

    // A command, with what to say when it worked; `retry` runs if the first needs a password
    // (udisks without asking first, then with the password prompt).
    function run(command, done, retry) {
        busy = true;
        runner.started = Date.now();
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
        property string mounting // a partition being connected, to learn why when it can't be
        property real started
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
            if (mounting) {
                if (code === 0) root.inUse = Object.assign({}, root.inUse, { [mounting]: false });
                else {
                    inUseCheck.path = mounting;
                    inUseCheck.since = started;
                    inUseCheck.running = true;
                }
                mounting = "";
            }
            root.refresh();
        }
    }

    // Files' Drives place follows drives connecting and disconnecting (files/drives.sh), a
    // moment after udisks says something changed.
    Process {
        running: true
        command: ["udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: placeSoon.restart()
        }
    }

    Timer {
        id: placeSoon
        interval: 1500
        onTriggered: Quickshell.execDetached(["bash", Quickshell.shellDir + "/../files/drives.sh"])
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
