// Control Panel: Sound. Where the sound goes and its volume, the microphone and its level,
// devices turned off (and on again), and each app's own volume while it plays.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config
import qs.services

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
            hint: "In this order: sound goes to the first one connected, so headphones put first take over when they connect"

            below: [
                SoundDeviceList {
                    Layout.fillWidth: true
                    manage: true
                }
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
            hint: "In this order: the first one connected is used"

            below: [
                SoundDeviceList {
                    Layout.fillWidth: true
                    inputs: true
                    manage: true
                }
            ]
        }
    }

    // Turned off (SoundDevices.qml): no app can use them until they're turned on again.
    CpSection {
        visible: SoundDevices.off.length > 0
        title: "Turned off"

        Repeater {
            model: SoundDevices.off

            CpRow {
                id: offRow
                required property var modelData
                glyph: modelData.input ? "audio-input-microphone-symbolic" : "audio-speakers-symbolic"
                label: modelData.description
                hint: modelData.input ? "Microphone · apps can't use it" : "Speakers · apps can't use it"

                PillButton {
                    text: "Turn on"
                    onClicked: SoundDevices.turnOn(offRow.modelData.name)
                }
            }
        }
    }

    // Sounds for what happens (Sounds.qml): signing in and out, a password asked for,
    // notifications, devices plugged in and out, screenshots.
    CpSection {
        title: "System sounds"

        CpRow {
            glyph: "preferences-desktop-notification-bell-symbolic"
            label: "Play sounds for events"
            hint: "Signing in and out, password requests, notifications, plugging devices in and out, screenshots"

            PillButton {
                visible: Sounds.on
                text: "Test"
                onClicked: Sounds.play("notification")
            }

            ToggleSwitch {
                on: Sounds.on
                onToggled: ShellSettings.set("systemSounds", !Sounds.on)
            }
        }

        CpRow {
            visible: Sounds.on && !Sounds.oceanInstalled
            glyph: "audio-x-generic-symbolic"
            label: "Get softer, fuller sounds"
            hint: "The Ocean sounds, from Arch Linux. Until then, the plain ones play."

            PillButton {
                text: page.gettingSounds ? "Installing..." : "Get"
                enabled: !page.gettingSounds
                onClicked: {
                    page.gettingSounds = true;
                    Desktop.installPackage("ocean-sound-theme");
                    oceanWait.restart();
                }
            }
        }
    }

    property bool gettingSounds: false

    // Looks for the sounds again while they're being installed.
    Timer {
        id: oceanWait
        interval: 3000
        repeat: true
        onTriggered: {
            Sounds.checkOcean();
            if (Sounds.oceanInstalled) {
                stop();
                page.gettingSounds = false;
                Sounds.play("notification");
            }
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
