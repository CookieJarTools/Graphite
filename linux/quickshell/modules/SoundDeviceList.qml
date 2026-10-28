// The speakers and headphones (or, with `inputs`, the microphones) to choose from; the
// chosen one becomes PipeWire's default, where every app's sound goes from then on.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config

ColumnLayout {
    id: root

    property bool inputs: false

    readonly property var current: inputs ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property var devices: Array.from(Pipewire.nodes.values)
        .filter(node => node.audio && !node.isStream && node.isSink === !root.inputs)

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
            readonly property bool chosen: root.current === modelData

            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.radiusSm
            color: rowMouse.containsMouse ? Theme.surface300 : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Glyph { name: root.inputs ? "audio-input-microphone-symbolic" : (/headphone|headset/i.test(row.modelData.description) ? "audio-headphones-symbolic" : "audio-speakers-symbolic") }

                UiText {
                    Layout.fillWidth: true
                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                    font.weight: row.chosen ? Font.DemiBold : Font.Normal
                }

                Glyph {
                    visible: row.chosen
                    name: "object-select-symbolic"
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.inputs) Pipewire.preferredDefaultAudioSource = row.modelData;
                    else Pipewire.preferredDefaultAudioSink = row.modelData;
                }
            }
        }
    }
}
