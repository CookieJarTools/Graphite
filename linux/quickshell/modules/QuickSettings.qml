// Quick settings: Wi-Fi, Bluetooth and Aeroplane mode tiles, the volume, and whatever media is
// playing. A tile's arrow opens its list in the panel (Wi-Fi networks to join, Bluetooth
// devices to pair, where the sound goes), with a way back; the gear opens the Control Panel.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.config
import qs.services

PanelFrame {
    id: root

    name: "quick"
    panelWidth: 380

    // "" (the tiles), "wifi", "bluetooth" or "sound".
    property string page: ""
    onOpenChanged: if (!open) page = ""
    Binding {
        target: Network
        property: "panelWatching"
        value: root.open && root.page === "wifi"
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property var connectedDevices: adapter ? Array.from(adapter.devices.values).filter(device => device.connected) : []

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // ---------- a list: its title, the way back, and the list ----------

    RowLayout {
        Layout.fillWidth: true
        visible: root.page !== ""
        spacing: Theme.space2

        BarButton {
            glyph: "go-previous-symbolic"
            onClicked: root.page = ""
        }

        UiText {
            Layout.fillWidth: true
            text: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", sound: "Sound output" })[root.page] || ""
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        ToggleSwitch {
            visible: root.page === "wifi" || root.page === "bluetooth"
            on: root.page === "wifi" ? Network.wifiEnabled : root.adapter !== null && root.adapter.enabled
            onToggled: {
                if (root.page === "wifi") Network.setWifi(!Network.wifiEnabled);
                else if (root.adapter) root.adapter.enabled = !root.adapter.enabled;
            }
        }
    }

    Flickable {
        id: pageList
        Layout.fillWidth: true
        visible: root.page !== ""
        implicitHeight: Math.min(contentHeight, 420)
        contentHeight: lists.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        WheelScroll { flickable: pageList }

        ColumnLayout {
            id: lists
            width: parent.width

            NetworkList {
                Layout.fillWidth: true
                visible: root.page === "wifi"
            }

            BluetoothList {
                Layout.fillWidth: true
                visible: root.page === "bluetooth"
                searching: root.open && root.page === "bluetooth"
            }

            SoundDeviceList {
                Layout.fillWidth: true
                visible: root.page === "sound"
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.page !== ""

        Item { Layout.fillWidth: true }

        MenuRow {
            text: "More settings"
            onClicked: ShellState.openSettings(({ wifi: "network", bluetooth: "devices", sound: "sound" })[root.page])
        }
    }

    // ---------- the tiles ----------

    GridLayout {
        Layout.fillWidth: true
        visible: root.page === ""
        columns: 2
        columnSpacing: Theme.space2
        rowSpacing: Theme.space2

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: Network.current ? Network.glyphFor(Network.current) : "network-wireless-offline-symbolic"
            label: "Wi-Fi"
            available: Network.available
            on: Network.wifiEnabled
            more: true
            detail: !Network.available ? "Unavailable" : Network.wifiEnabled ? (Network.ssid || "Not connected") : Network.wired ? "Off · wired" : "Off"
            onToggled: Network.setWifi(!Network.wifiEnabled)
            onMoreClicked: root.page = "wifi"
        }

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: "bluetooth-active-symbolic"
            label: "Bluetooth"
            available: root.adapter !== null
            on: root.adapter ? root.adapter.enabled : false
            more: true
            detail: !root.adapter ? "Unavailable" : !root.adapter.enabled ? "Off" : root.connectedDevices.length === 1 ? root.connectedDevices[0].name : root.connectedDevices.length > 1 ? root.connectedDevices.length + " connected" : "On"
            onToggled: { if (root.adapter) root.adapter.enabled = !root.adapter.enabled; }
            onMoreClicked: root.page = "bluetooth"
        }

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: "airplane-mode-symbolic"
            label: "Aeroplane mode"
            on: Network.airplane
            detail: Network.airplane ? "On" : "Off"
            onToggled: Network.setAirplane(!Network.airplane)
        }

        Tile {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            glyph: "night-light-symbolic"
            label: "Night light"
            on: Displays.nightLight
            detail: Displays.nightLight ? "Warmer colours" : "Off"
            onToggled: Displays.setNightLight(!Displays.nightLight)
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space2
        visible: root.page === "" && root.audio !== null

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
            Layout.preferredWidth: 28
            horizontalAlignment: Text.AlignRight
            text: root.audio ? Math.round(root.audio.volume * 100) : ""
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }

        // Where the sound goes: the speakers, headphones...
        BarButton {
            glyph: "go-next-symbolic"
            onClicked: root.page = "sound"
        }
    }

    // Now playing (MPRIS: browsers, Spotify, mpv...).
    Rectangle {
        Layout.fillWidth: true
        visible: root.page === "" && root.player !== null
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

    // The battery (only a real one), and the way to the Control Panel.
    RowLayout {
        Layout.fillWidth: true
        visible: root.page === ""
        spacing: Theme.space2

        readonly property var battery: UPower.displayDevice
        readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent

        UiText {
            Layout.fillWidth: true
            text: parent.hasBattery
                ? "Battery " + Math.round(parent.battery.percentage * (parent.battery.percentage <= 1 ? 100 : 1)) + "%" + (UPower.onBattery ? "" : " · charging")
                : ""
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
        }

        BarButton {
            glyph: "emblem-system-symbolic"
            onClicked: ShellState.openSettings("")
        }
    }
}
