// The speakers and headphones (or, with `inputs`, the microphones), in the order to use them
// (SoundDevices.qml): the first one connected is used, and choosing one here uses it now. With
// `manage` (the Control Panel) the list includes the ones not connected, numbered, and each
// moves up or down, turns off, or (not connected) is forgotten; quick settings shows the
// connected ones only.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config
import qs.services

ColumnLayout {
    id: root

    property bool inputs: false
    property bool manage: false

    readonly property var current: inputs ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    // Read again whenever a device comes or goes, or the order or the turned-off ones change.
    readonly property var devices: {
        SoundDevices.connected;
        SoundDevices.order;
        SoundDevices.off;
        const all = SoundDevices.ordered(root.inputs);
        return root.manage ? all : all.filter(device => device.node);
    }

    spacing: 2

    UiText {
        Layout.fillWidth: true
        visible: root.devices.length === 0
        text: root.inputs ? "No microphone found." : "No speakers or headphones found."
        color: Theme.inkMuted
    }

    Repeater {
        model: root.devices

        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool connected: modelData.node !== null
            readonly property bool chosen: connected && root.current === modelData.node

            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.radiusSm
            color: rowHover.hovered && connected ? Theme.surface300 : "transparent"

            // Over the row or its buttons.
            HoverHandler { id: rowHover }

            MouseArea {
                anchors.fill: parent
                enabled: row.connected
                onClicked: {
                    if (root.inputs) Pipewire.preferredDefaultAudioSource = row.modelData.node;
                    else Pipewire.preferredDefaultAudioSink = row.modelData.node;
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3
                opacity: row.connected ? 1 : 0.55

                UiText {
                    visible: root.manage
                    Layout.preferredWidth: 14
                    text: row.index + 1
                    color: Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }

                Glyph { name: root.inputs ? "audio-input-microphone-symbolic" : (/headphone|headset|ace|buds|airpods/i.test(row.modelData.description) || row.modelData.name.startsWith("bluez") ? "audio-headphones-symbolic" : "audio-speakers-symbolic") }

                UiText {
                    Layout.fillWidth: true
                    text: row.modelData.description + (row.connected ? "" : "  ·  Not connected")
                    font.weight: row.chosen ? Font.DemiBold : Font.Normal
                }

                BarButton {
                    visible: root.manage && rowHover.hovered && row.index > 0
                    glyph: "go-up-symbolic"
                    onClicked: SoundDevices.move(root.inputs, row.modelData.name, -1)
                }

                BarButton {
                    visible: root.manage && rowHover.hovered && row.index < root.devices.length - 1
                    glyph: "go-down-symbolic"
                    onClicked: SoundDevices.move(root.inputs, row.modelData.name, 1)
                }

                PillButton {
                    visible: root.manage && rowHover.hovered
                    text: row.connected ? "Turn off" : "Forget"
                    onClicked: {
                        if (row.connected) SoundDevices.turnOff(row.modelData, root.inputs);
                        else SoundDevices.forget(root.inputs, row.modelData.name);
                    }
                }

                Glyph {
                    visible: row.chosen
                    name: "object-select-symbolic"
                }
            }
        }
    }
}
