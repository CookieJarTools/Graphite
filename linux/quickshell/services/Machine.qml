pragma Singleton
// The computer itself, for the Control Panel: what it is (name, processor, memory, graphics,
// Graphite's version), its storage, the time zone and clock, the firewall, the people who can
// sign in, startup apps and the default web browser.
//
// Changes that need the administrator go through graphite-admin (pkexec asks for the
// password); the time zone, the clock and the computer's name go straight through systemd,
// which 50-graphite.rules allows an administrator at the computer.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string admin: "/usr/local/lib/graphite/graphite-admin"

    // ---------- about ----------

    property var about: ({})

    Process {
        id: aboutReader
        command: ["bash", "-c", [
            "echo \"host=$(hostnamectl hostname 2>/dev/null || cat /etc/hostname)\"",
            "echo \"cpu=$(sed -n 's/^model name\\s*: //p' /proc/cpuinfo | head -1)\"",
            "echo \"cores=$(nproc)\"",
            "echo \"memory=$(awk '/MemTotal/ {printf \"%.0f\", $2/1048576}' /proc/meminfo)\"",
            "echo \"gpu=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | sed 's/^[^:]*: //' | head -2 | paste -sd ';')\"",
            "echo \"kernel=$(uname -r)\"",
            `echo "version=$(git -C "${Quickshell.shellDir}/../.." log -1 --format='%h, %cd' --date=format:'%-d %B %Y' 2>/dev/null)"`,
            "echo \"model=$(cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null | paste -sd ' ')\"",
            "echo \"encrypted=$(lsblk -no TYPE,FSTYPE | grep -c crypt)\"",
            "echo \"timezone=$(timedatectl show -p Timezone --value)\"",
            "echo \"ntp=$(timedatectl show -p NTP --value)\"",
            "echo \"firewall=$(grep -qs '^ENABLED=yes' /etc/ufw/ufw.conf && echo on || echo off)\"",
            "echo \"hasFirewall=$(command -v ufw >/dev/null && echo yes || echo no)\"",
            "echo \"browser=$(xdg-settings get default-web-browser 2>/dev/null)\""
        ].join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const read = {};
                for (const line of this.text.split("\n")) {
                    const at = line.indexOf("=");
                    if (at > 0) read[line.slice(0, at)] = line.slice(at + 1).trim();
                }
                root.about = read;
            }
        }
    }

    // ---------- storage ----------

    property var storage: [] // [{ mount, size, used, free, percent }] in bytes

    Process {
        id: storageReader
        command: ["sh", "-c", "df -B1 --output=target,size,used,avail -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs -x vboxsf | tail -n +2"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.storage = this.text.split("\n").map(line => line.trim().split(/\s+/)).filter(parts => parts.length === 4 && !parts[0].startsWith("/boot"))
                    .map(parts => ({ mount: parts[0], size: Number(parts[1]), used: Number(parts[2]), free: Number(parts[3]), percent: Number(parts[2]) / Math.max(1, Number(parts[1])) }));
            }
        }
    }

    function size(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let value = bytes;
        let unit = 0;
        while (value >= 1000 && unit < units.length - 1) {
            value /= 1000;
            unit += 1;
        }
        return (value >= 100 || unit === 0 ? Math.round(value) : value.toFixed(1)) + " " + units[unit];
    }

    property bool cleaning: false

    function clean() {
        cleaning = true;
        cleaner.running = true;
    }

    Process {
        id: cleaner
        command: ["sh", "-c", `pkexec ${root.admin} clean; flatpak uninstall --user --unused -y --noninteractive >/dev/null 2>&1; rm -rf "$HOME/.cache/thumbnails"`]
        onExited: {
            root.cleaning = false;
            storageReader.running = true;
        }
    }

    // ---------- time ----------

    property var zones: []

    Process {
        id: zoneReader
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: root.zones = this.text.split("\n").filter(zone => zone.includes("/")) }
    }

    function loadZones() {
        if (zones.length === 0) zoneReader.running = true;
    }

    function setTimeZone(zone) {
        run(["timedatectl", "set-timezone", zone]);
    }

    function setAutomaticTime(on) {
        run(["timedatectl", "set-ntp", on ? "true" : "false"]);
    }

    function setHostname(name) {
        const clean = name.trim().toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
        if (clean) run(["hostnamectl", "set-hostname", clean]);
    }

    // ---------- security ----------

    function setFirewall(on) {
        run(["pkexec", admin, "firewall", on ? "on" : "off"]);
    }

    // ---------- people ----------

    property var people: [] // [{ name, full, admin, me }]

    Process {
        id: peopleReader
        command: ["sh", "-c", "getent group wheel | cut -d: -f4; awk -F: '$3 >= 1000 && $3 < 60000 { print $1 \":\" $5 }' /etc/passwd; id -un"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(line => line.length);
                const admins = (lines[0] || "").split(",");
                const me = lines[lines.length - 1];
                root.people = lines.slice(1, -1).map(line => {
                    const [name, gecos] = line.split(":");
                    return { name: name, full: (gecos || "").split(",")[0] || name, admin: admins.includes(name), me: name === me };
                });
            }
        }
    }

    property string accountMessage: ""

    // Each runs graphite-admin through pkexec with the secret on its input, never its arguments.
    function addPerson(name, full, password, isAdmin) {
        withSecret(["pkexec", admin, "user-add", name, full, isAdmin ? "yes" : "no"], password, "Added " + full);
    }

    function removePerson(name) {
        run(["pkexec", admin, "user-remove", name], "Removed");
    }

    function setPassword(name, password) {
        withSecret(["pkexec", admin, "user-password", name], password, "Password changed");
    }

    function setAdmin(name, isAdmin) {
        run(["pkexec", admin, "user-admin", name, isAdmin ? "yes" : "no"]);
    }

    function setHint(name, hint) {
        withSecret(["pkexec", admin, "hint", name], hint || "\n", hint ? "Hint saved" : "Hint removed");
    }

    // The sign-in PIN (4 digits); an empty one removes it.
    property bool hasPin: false

    Process {
        id: pinReader
        command: ["sh", "-c", "test -d \"/var/lib/graphite/pins/$USER\""]
        onExited: code => root.hasPin = code === 0
    }

    function setPin(name, pin) {
        withSecret(["pkexec", admin, "pin", name], pin || "
", pin ? "PIN saved: sign in with it from now on" : "PIN removed");
    }

    function setFullName(name, full) {
        run(["pkexec", admin, "user-fullname", name, full], "Name changed");
    }

    // ---------- apps ----------

    // Startup apps: ~/.config/autostart entries (started by system/autostart.sh at sign-in).
    property var startup: []

    Process {
        id: startupReader
        command: ["sh", "-c", "for f in \"$HOME/.config/autostart\"/*.desktop; do [ -f \"$f\" ] || continue; grep -qi '^Hidden=true' \"$f\" && continue; basename \"$f\" .desktop; done"]
        stdout: StdioCollector { onStreamFinished: root.startup = this.text.split("\n").filter(line => line) }
    }

    function addStartup(entryId) {
        const id = String(entryId).replace(/\.desktop$/, "");
        run(["sh", "-c", `mkdir -p "$HOME/.config/autostart" && f=$(for d in "$HOME/.local/share/applications" /usr/share/applications "$HOME/.local/share/flatpak/exports/share/applications" /var/lib/flatpak/exports/share/applications; do [ -f "$d/${id}.desktop" ] && echo "$d/${id}.desktop" && break; done) && cp "$f" "$HOME/.config/autostart/${id}.desktop"`]);
    }

    function removeStartup(entryId) {
        run(["rm", "-f", Quickshell.env("HOME") + "/.config/autostart/" + entryId + ".desktop"]);
    }

    function setBrowser(entryId) {
        run(["xdg-settings", "set", "default-web-browser", String(entryId).replace(/\.desktop$/, "") + ".desktop"]);
    }

    // ---------- running things ----------

    property bool busy: false

    function run(command, done) {
        busy = true;
        runner.done = done || "";
        runner.command = command;
        runner.running = true;
    }

    function withSecret(command, secret, done) {
        busy = true;
        secretRunner.done = done || "";
        secretRunner.secret = secret;
        secretRunner.command = command;
        secretRunner.running = true;
    }

    Process {
        id: runner
        property string done
        stderr: StdioCollector { id: runnerError }
        onExited: code => root.finished(code, done, runnerError.text)
    }

    Process {
        id: secretRunner
        property string done
        property string secret
        stdinEnabled: true
        stderr: StdioCollector { id: secretError }
        onStarted: {
            write(secret + "\n");
            secret = "";
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            root.finished(code, done, secretError.text);
        }
    }

    function finished(code, done, error) {
        busy = false;
        // 126/127: the password box was closed.
        accountMessage = code === 0 ? done : code === 126 || code === 127 ? "" : (error.trim().split("\n").pop() || "That didn't work");
        refresh();
    }

    function refresh() {
        aboutReader.running = true;
        storageReader.running = true;
        peopleReader.running = true;
        startupReader.running = true;
        pinReader.running = true;
    }
}
