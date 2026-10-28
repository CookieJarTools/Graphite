pragma Singleton
// Power: the power mode (power-profiles-daemon: power-saver, balanced, performance) and what
// happens when the computer is left alone: lock, screen off, sleep, after so many minutes
// (0 for never). The times are kept in settings.json and written as hypridle's settings
// (~/.config/hypr/hypridle.conf), which starts again to read them.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // In a virtual machine sleeping does no good (and stops whatever runs in it): no sleep timer.
    property bool virtualMachine: false
    property string profile: "balanced"
    property var profiles: ["power-saver", "balanced", "performance"]
    readonly property var idle: ShellSettings.values ? (ShellSettings.values.idle || {}) : ({})

    function refresh() {
        reader.running = true;
    }

    Process {
        id: virt
        command: ["systemd-detect-virt", "--vm"]
        onExited: code => {
            root.virtualMachine = code === 0;
            if (ShellSettings.values) root.writeIdle();
        }
    }

    Process {
        id: reader
        command: ["sh", "-c", "powerprofilesctl get; powerprofilesctl list | sed -n 's/^[ *]*\\([a-z-]*\\):$/\\1/p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").map(line => line.trim()).filter(line => line);
                if (lines.length === 0) return;
                root.profile = lines[0];
                const listed = lines.slice(1);
                if (listed.length) root.profiles = ["power-saver", "balanced", "performance"].filter(name => listed.includes(name));
            }
        }
    }

    function setProfile(name) {
        profile = name;
        Quickshell.execDetached(["powerprofilesctl", "set", name]);
    }

    function setIdle(key, minutes) {
        ShellSettings.update(settings => {
            settings.idle = Object.assign({}, settings.idle || {});
            settings.idle[key] = minutes;
        });
        writeIdle();
    }

    function writeIdle() {
        const idle = (ShellSettings.values || {}).idle || {};
        const blocks = [
            "# Written by Graphite's Control Panel (services/Power.qml).",
            "general {",
            "    lock_cmd = qs -c graphite ipc call lock lock",
            "    before_sleep_cmd = qs -c graphite ipc call lock lock",
            "    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'",
            "}"
        ];
        const listener = (minutes, onTimeout, onResume) => {
            if (!minutes) return;
            blocks.push("listener {", `    timeout = ${minutes * 60}`, `    on-timeout = ${onTimeout}`);
            if (onResume) blocks.push(`    on-resume = ${onResume}`);
            blocks.push("}");
        };
        listener(idle.lock, "loginctl lock-session");
        listener(idle.screenOff, "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'", "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'");
        if (!virtualMachine) listener(idle.sleep, "systemctl suspend");
        conf.setText(blocks.join("\n") + "\n");
    }

    FileView {
        id: conf
        path: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"
        printErrors: false
        onSaved: Quickshell.execDetached(["sh", "-c", "pkill -x hypridle; sleep 0.3; command -v hypridle >/dev/null && exec hypridle"])
    }

    // hypridle's settings, written once at the start of a session (they may be new).
    Timer {
        interval: 2000
        running: true
        onTriggered: {
            root.refresh();
            virt.running = true;
        }
    }
}
