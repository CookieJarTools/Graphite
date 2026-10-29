// Control Panel: Sound. Where the sound goes and its volume, the microphone and its level,
// and each app's own volume while it plays.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config

ColumnLayout {
    id: page

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var streams: Array.from(Pipewire.nodes.values).filter(node => node.isStream && node.isSink && node.audio)

    spacing: 0

    PwObjectTracker { objects: [page.sink, page.source].concat(page.streams) }

    CpSection {
        title: "Output"

        CpRow {
            glyph: "audio-volume-high-symbolic"
            label: "Volume"
            enabled: page.sink !== null

            SliderBar {
                Layout.preferredWidth: 220
                value: page.sink && page.sink.audio ? page.sink.audio.volume : 0
                dimmed: page.sink && page.sink.audio ? page.sink.audio.muted : false
                onMoved: value => {
                    if (!page.sink || !page.sink.audio) return;
                    page.sink.audio.volume = value;
                    if (value > 0) page.sink.audio.muted = false;
                }
            }

            ToggleSwitch {
                on: page.sink && page.sink.audio ? !page.sink.audio.muted : false
                onToggled: { if (page.sink && page.sink.audio) page.sink.audio.muted = !page.sink.audio.muted; }
            }
        }

        CpRow {
            label: "Play sound through"

            below: [
                SoundDeviceList { Layout.fillWidth: true }
            ]
        }
    }

    CpSection {
        title: "Input"

        CpRow {
            glyph: "audio-input-microphone-symbolic"
            label: "Microphone volume"
            enabled: page.source !== null

            SliderBar {
                Layout.preferredWidth: 220
                value: page.source && page.source.audio ? page.source.audio.volume : 0
                dimmed: page.source && page.source.audio ? page.source.audio.muted : false
                onMoved: value => {
                    if (!page.source || !page.source.audio) return;
                    page.source.audio.volume = value;
                    if (value > 0) page.source.audio.muted = false;
                }
            }

            ToggleSwitch {
                on: page.source && page.source.audio ? !page.source.audio.muted : false
                onToggled: { if (page.source && page.source.audio) page.source.audio.muted = !page.source.audio.muted; }
            }
        }

        CpRow {
            label: "Record sound from"

            below: [
                SoundDeviceList {
                    Layout.fillWidth: true
                    inputs: true
                }
            ]
        }
    }

    CpSection {
        title: "Apps"

        CpRow {
            visible: page.streams.length === 0
            label: "Nothing is playing"
            hint: "Apps playing sound show here with their own volume"
        }

        Repeater {
            model: page.streams

            CpRow {
                id: appRow
                required property var modelData
                label: modelData.properties["application.name"] || modelData.description || modelData.name
                hint: modelData.properties["media.name"] || ""

                SliderBar {
                    Layout.preferredWidth: 220
                    value: appRow.modelData.audio ? appRow.modelData.audio.volume : 0
                    onMoved: value => { if (appRow.modelData.audio) appRow.modelData.audio.volume = value; }
                }
            }
        }
    }
}
