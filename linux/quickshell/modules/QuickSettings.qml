// Quick settings: Wi-Fi and Bluetooth tiles, the volume, and whatever media is playing.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import qs.config
import qs.services

PanelFrame {
    id: root

    name: "quick"
    panelWidth: 360
    onOpenChanged: Network.watching = open

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space2

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: "network-wireless-signal-excellent-symbolic"
            label: "Wi-Fi"
            available: Network.available
            on: Network.wifiEnabled
            detail: !Network.available ? "Unavailable" : Network.wifiEnabled ? (Network.ssid || "On") : "Off"
            onToggled: Network.setWifi(!Network.wifiEnabled)
        }

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: "bluetooth-active-symbolic"
            label: "Bluetooth"
            available: root.adapter !== null
            on: root.adapter ? root.adapter.enabled : false
            detail: !root.adapter ? "Unavailable" : root.adapter.enabled ? "On" : "Off"
            onToggled: { if (root.adapter) root.adapter.enabled = !root.adapter.enabled; }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space2
        visible: root.audio !== null

        BarButton {
            glyph: root.audio && root.audio.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
            onClicked: { if (root.audio) root.audio.muted = !root.audio.muted; }
        }

        SliderBar {
            Layout.fillWidth: true
            value: root.audio ? root.audio.volume : 0
            dimmed: root.audio ? root.audio.muted : false
            onMoved: value => {
                if (!root.audio) return;
                root.audio.volume = value;
                if (value > 0) root.audio.muted = false;
            }
        }

        UiText {
            Layout.preferredWidth: 32
            horizontalAlignment: Text.AlignRight
            text: root.audio ? Math.round(root.audio.volume * 100) : ""
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }
    }

    // Now playing (MPRIS: browsers, Spotify, mpv...).
    Rectangle {
        Layout.fillWidth: true
        visible: root.player !== null
        implicitHeight: 72
        radius: Theme.radiusMd
        color: Theme.surface100
        border.color: Theme.line
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space3

            Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: Theme.radiusSm
                color: Theme.surface300
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.player ? root.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                UiText {
                    Layout.fillWidth: true
                    text: root.player ? root.player.trackTitle : ""
                    font.weight: Font.DemiBold
                }

                UiText {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackArtist || root.player.identity) : ""
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            BarButton {
                glyph: "media-skip-backward-symbolic"
                opacity: root.player && root.player.canGoPrevious ? 1 : 0.35
                onClicked: { if (root.player && root.player.canGoPrevious) root.player.previous(); }
            }

            BarButton {
                glyph: root.player && root.player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                onClicked: { if (root.player) root.player.togglePlaying(); }
            }

            BarButton {
                glyph: "media-skip-forward-symbolic"
                opacity: root.player && root.player.canGoNext ? 1 : 0.35
                onClicked: { if (root.player && root.player.canGoNext) root.player.next(); }
            }
        }
    }
}
