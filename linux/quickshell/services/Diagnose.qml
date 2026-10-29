pragma Singleton
// Troubleshoot: system/diagnose.sh's checks (the graphics driver, your folders, Firefox,
// Flathub apps on NVIDIA, the desktop's helpers, the internet) and the apps that didn't open
// lately, with a fix for each problem that has one.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool running: false
    property var checks: []   // [{ id, state: "ok" | "warn" | "fail", title, detail, fix }]
    property var failures: [] // [{ time, app, words }]
    property string fixing: ""

    function run() {
        if (running) return;
        running = true;
        reader.running = true;
    }

    Process {
        id: reader
        command: ["bash", Quickshell.shellDir + "/../system/diagnose.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                const checks = [];
                const failures = [];
                for (const line of this.text.split("\n")) {
                    let match = /^CHECK (\S+) (\S+) (.*)$/.exec(line);
                    if (match) {
                        const [title, detail, fix] = match[3].split("|");
                        checks.push({ id: match[1], state: match[2], title: title, detail: detail || "", fix: fix || "" });
                        continue;
                    }
                    match = /^FAILED (.*)$/.exec(line);
                    if (match) {
                        const [time, app, words] = match[1].split("|");
                        failures.push({ time: new Date(Number(time) * 1000), app: app, words: words || "" });
                    }
                }
                root.checks = checks;
                root.failures = failures;
                root.running = false;
            }
        }
    }

    readonly property var fixLabels: ({
        drivers: "Install drivers",
        home: "Fix",
        clean: "Free up space",
        firefox: "Reset Firefox",
        flatpak: "Fix",
        portals: "Restart"
    })

    function fix(id) {
        fixing = id;
        const commands = {
            home: `pkexec /usr/local/lib/graphite/graphite-admin fix-home "$USER"`,
            firefox: `for f in "$HOME/.mozilla/firefox/profiles.ini" "$HOME/.config/mozilla/firefox/profiles.ini"; do [ -f "$f" ] && mv "$f" "$f.old"; done`,
            flatpak: `flatpak update --user -y --noninteractive; pkexec /usr/local/lib/graphite/graphite-admin flatpak-update`,
            portals: "systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service xdg-desktop-portal.service"
        };
        if (id === "drivers") {
            Desktop.setUpGaming();
            fixing = "";
            return;
        }
        if (id === "clean") {
            Machine.clean();
            fixing = "";
            return;
        }
        fixer.command = ["sh", "-c", commands[id] || "true"];
        fixer.running = true;
    }

    Process {
        id: fixer
        onExited: {
            root.fixing = "";
            root.run();
        }
    }
}
