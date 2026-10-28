pragma Singleton
// Wi-Fi and the wired connection, through NetworkManager (Quickshell.Networking): whether the
// radio is on, the networks in range (scanned while a list of them is on screen: `watching`),
// connecting with a password, forgetting, and hidden networks (by nmcli, which the module has
// no call for). Aeroplane mode turns Wi-Fi and Bluetooth off together.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

Singleton {
    id: root

    // Whether a list of networks is on screen (quick settings, the Control Panel): it scans then.
    property bool panelWatching: false
    property bool windowWatching: false
    readonly property bool watching: panelWatching || windowWatching

    readonly property var devices: Networking.devices ? Array.from(Networking.devices.values) : []
    readonly property var wifiDevice: devices.find(device => device.type === DeviceType.Wifi) || null
    readonly property var wiredDevice: devices.find(device => device.type === DeviceType.Wired) || null

    readonly property bool available: wifiDevice !== null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wired: wiredDevice !== null && wiredDevice.connected
    readonly property bool airplane: !Networking.wifiEnabled && !(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)

    // Networks in range with a name: the connected one first, then by signal.
    readonly property var networks: {
        if (!wifiDevice || !wifiEnabled) return [];
        return Array.from(wifiDevice.networks.values)
            .filter(network => network.name)
            .sort((first, second) => (second.connected - first.connected) || (second.signalStrength - first.signalStrength));
    }
    readonly property var current: networks.find(network => network.connected) || null
    readonly property string ssid: current ? current.name : ""
    readonly property bool online: wired || current !== null

    // Scanning only while someone is looking at the list.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.watching && root.wifiEnabled
        when: root.wifiDevice !== null
    }

    function setWifi(on) {
        Networking.wifiEnabled = on;
    }

    function setAirplane(on) {
        Networking.wifiEnabled = !on;
        if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !on;
    }

    function isSecure(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe;
    }

    // 0 to 4 bars, as the glyph shows them.
    function bars(network) {
        const strength = network ? network.signalStrength : 0;
        const value = strength > 1 ? strength / 100 : strength;
        return value > 0.75 ? 4 : value > 0.5 ? 3 : value > 0.25 ? 2 : 1;
    }

    function glyphFor(network) {
        return "network-wireless-signal-" + ["weak", "weak", "ok", "good", "excellent"][bars(network)] + "-symbolic";
    }

    function connect(network, password) {
        if (password) network.connectWithPsk(password);
        else network.connect();
    }

    // A hidden network: its name and password typed in.
    property string hiddenResult: "" // "", "joining", "ok" or what went wrong

    function joinHidden(name, password) {
        hiddenResult = "joining";
        const command = ["nmcli", "device", "wifi", "connect", name, "hidden", "yes"];
        if (password) command.push("password", password);
        hidden.command = command;
        hidden.running = true;
    }

    Process {
        id: hidden
        stderr: StdioCollector { id: hiddenError }
        onExited: code => {
            root.hiddenResult = code === 0 ? "ok"
                : /secrets|password/i.test(hiddenError.text) ? "Wrong password"
                : "Couldn't find or join that network";
        }
    }

    // Network settings beyond these (VPNs, a fixed address): NetworkManager's own editor.
    function openAdvanced() {
        Quickshell.execDetached(["nm-connection-editor"]);
    }
}
