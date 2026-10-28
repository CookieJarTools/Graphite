pragma Singleton
// Wi-Fi through NetworkManager's nmcli: whether the radio is on, the connected network's
// name, and switching the radio. Read every few seconds while someone is looking (the quick
// settings panel sets watching).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool watching: false
    property bool wifiEnabled: false
    property string ssid: ""
    property bool available: false // nmcli answered
    property bool online: true     // some connection is up (the bar dims its glyph otherwise)
    property bool wired: false     // an Ethernet connection is up

    function refresh() {
        radio.running = true;
        active.running = true;
        devices.running = true;
    }

    Process {
        id: devices
        command: ["nmcli", "-t", "-f", "TYPE,STATE", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.split("\n").filter(row => row.trim());
                if (rows.length === 0) return;
                root.wired = rows.some(row => row.startsWith("ethernet:connected"));
                root.online = rows.some(row => /^(ethernet|wifi):connected$/.test(row));
            }
        }
    }

    // The bar's glyph keeps up slowly even while nobody has the panel open.
    Timer {
        interval: 15000
        repeat: true
        running: !root.watching
        triggeredOnStart: true
        onTriggered: devices.running = true
    }

    function setWifi(on) {
        wifiEnabled = on; // at once; the next read confirms
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        settle.restart();
    }

    Process {
        id: radio
        command: ["nmcli", "-t", "-f", "WIFI", "general"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = this.text.trim().length > 0;
                root.wifiEnabled = this.text.trim() === "enabled";
            }
        }
    }

    Process {
        id: active
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = this.text.split("\n").find(row => row.startsWith("yes:"));
                root.ssid = line ? line.slice(4) : "";
            }
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.watching
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // A switched radio takes a moment to report its new state.
    Timer {
        id: settle
        interval: 1500
        onTriggered: root.refresh()
    }
}
