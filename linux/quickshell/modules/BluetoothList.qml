// Bluetooth devices, for quick settings and the Control Panel: "Your devices" (paired) to
// connect, disconnect or forget, and "Nearby" ones found while the list shows (the adapter
// searches while `searching` is set by the owner) to pair with a click. Paired devices are
// trusted too, so they come back by themselves.
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.config

ColumnLayout {
    id: root

    property bool searching: false

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var devices: adapter ? Array.from(adapter.devices.values) : []
    readonly property var paired: devices.filter(device => device.paired).sort((first, second) => (second.connected - first.connected) || first.name.localeCompare(second.name))
    // Nearby: named ones only (the rest are anonymous beacons nobody can recognise).
    readonly property var nearby: devices.filter(device => !device.paired && device.deviceName)

    property string opened: ""

    spacing: 2

    Binding {
        target: root.adapter
        property: "discovering"
        value: root.searching && root.on
        when: root.adapter !== null
    }

    UiText {
        Layout.fillWidth: true
        visible: !root.adapter || !root.on
        text: !root.adapter ? "This computer has no Bluetooth." : "Bluetooth is off."
        color: Theme.inkMuted
    }

    Heading {
        visible: root.on && root.paired.length > 0
        text: "Your devices"
    }

    Repeater {
        model: root.on ? root.paired : []
        DeviceRow {}
    }

    Heading {
        visible: root.on
        text: root.nearby.length ? "Nearby" : "Looking for devices... (put yours in pairing mode)"
    }

    Repeater {
        model: root.on ? root.nearby : []
        DeviceRow {}
    }

    component Heading: UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    component DeviceRow: Rectangle {
        id: row
        required property var modelData
        readonly property bool isOpen: root.opened === modelData.address
        readonly property bool busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + Theme.space2 * 2
        radius: Theme.radiusSm
        color: isOpen ? Theme.surface100 : rowMouse.containsMouse ? Theme.surface300 : "transparent"

        // Paired: trusted from then on, so it reconnects without asking.
        Connections {
            target: row.modelData
            function onPairedChanged() {
                if (!row.modelData.paired) return;
                row.modelData.trusted = true;
                row.modelData.connect();
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (!row.modelData.paired) {
                    row.modelData.pair();
                    return;
                }
                root.opened = row.isOpen ? "" : row.modelData.address;
            }
        }

        ColumnLayout {
            id: content
            x: Theme.space3
            y: Theme.space2
            width: parent.width - Theme.space3 * 2
            spacing: Theme.space2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space3

                Glyph { name: (row.modelData.icon || "bluetooth") + "-symbolic" }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    UiText {
                        Layout.fillWidth: true
                        text: row.modelData.name || row.modelData.address
                        font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                    }

                    UiText {
                        Layout.fillWidth: true
                        text: row.modelData.pairing ? "Pairing..."
                            : row.modelData.state === BluetoothDeviceState.Connecting ? "Connecting..."
                            : row.modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting..."
                            : row.modelData.connected ? "Connected" + (row.modelData.batteryAvailable ? ", battery " + Math.round(row.modelData.battery * (row.modelData.battery <= 1 ? 100 : 1)) + "%" : "")
                            : row.modelData.paired ? "Not connected" : "Click to pair"
                        color: row.modelData.connected ? Theme.success : Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: row.isOpen
                spacing: Theme.space2

                Item { Layout.fillWidth: true }

                PillButton {
                    text: "Forget"
                    onClicked: {
                        row.modelData.forget();
                        root.opened = "";
                    }
                }

                PillButton {
                    primary: !row.modelData.connected
                    enabled: !row.busy
                    text: row.modelData.connected ? "Disconnect" : "Connect"
                    onClicked: row.modelData.connected ? row.modelData.disconnect() : row.modelData.connect()
                }
            }
        }
    }
}
