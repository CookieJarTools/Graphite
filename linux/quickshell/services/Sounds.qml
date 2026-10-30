pragma Singleton
// System sounds, as Windows plays them: signing in and out, a password asked for, a
// notification, a warning or an error, a USB device plugged in or out, a screenshot, a task
// finished. The sounds are KDE's Ocean theme (Arch's ocean-sound-theme: softer and fuller than
// the plain freedesktop set, which stands in until it's installed), by their freedesktop names,
// played through PipeWire as event sounds. Off with the Control Panel's Sound page
// (settings.json's systemSounds).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool on: ShellSettings.values ? ShellSettings.values.systemSounds !== false : false
    readonly property bool oceanInstalled: oceanCheck.found

    // Each event's sounds, the first the theme has playing.
    readonly property var events: ({
        login: ["desktop-login", "service-login"],
        logout: ["desktop-logout", "service-logout"],
        password: ["dialog-warning-auth", "dialog-question", "dialog-information"],
        notification: ["message-new-instant", "message", "bell"],
        warning: ["dialog-warning", "dialog-information"],
        error: ["dialog-error", "dialog-warning"],
        deviceAdded: ["device-added"],
        deviceRemoved: ["device-removed"],
        screenshot: ["screen-capture", "camera-shutter"],
        done: ["completion-success", "outcome-success", "complete"]
    })

    // The shell command that plays one (also used where something has to wait for the sound,
    // as signing out, restarting and shutting down do). In a subshell of its own, so what comes
    // after it still runs, and never more than a few seconds, should the sound server be stuck.
    function command(event) {
        if (!on) return "true";
        const names = (events[event] || [event]).join(" ");
        return `(for name in ${names}; do for theme in ocean freedesktop; do for ext in oga ogg wav; do f=/usr/share/sounds/$theme/stereo/$name.$ext; [ -f "$f" ] && { timeout 4 pw-play --media-role=Notification --volume=0.7 "$f" 2>/dev/null; exit 0; }; done; done; done)`;
    }

    // A burst (several notifications at once, a hub's devices) plays once.
    property var lastPlayed: ({})

    function play(event) {
        if (!on) return;
        const now = Date.now();
        if (now - (lastPlayed[event] || 0) < 600) return;
        lastPlayed[event] = now;
        Quickshell.execDetached(["sh", "-c", command(event)]);
    }

    // Signing in: once a session (a reload or restart of the shell doesn't replay it).
    Timer {
        running: ShellSettings.loaded
        interval: 400
        onTriggered: Quickshell.execDetached(["sh", "-c", `marker="$XDG_RUNTIME_DIR/graphite-signed-in"; [ -e "$marker" ] || { touch "$marker"; ${root.command("login")}; }`])
    }

    // USB devices plugged in or out (hubs and the devices on them each count once).
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb/usb_device"]
        stdout: SplitParser {
            onRead: line => {
                if (/\sadd\s/.test(line)) root.play("deviceAdded");
                else if (/\sremove\s/.test(line)) root.play("deviceRemoved");
            }
        }
    }

    Process {
        id: oceanCheck
        property bool found: false
        running: true
        command: ["test", "-d", "/usr/share/sounds/ocean"]
        onExited: code => found = code === 0
    }

    function checkOcean() {
        oceanCheck.running = true;
    }
}
