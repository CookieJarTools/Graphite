// Control Panel: Network & internet. Wi-Fi (on or off, the networks to join, hidden ones),
// the cable, aeroplane mode, and NetworkManager's own editor for VPNs and fixed addresses.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    spacing: 0

    CpSection {
        CpRow {
            glyph: Network.current ? Network.glyphFor(Network.current) : "network-wireless-offline-symbolic"
            label: "Wi-Fi"
            hint: !Network.available ? "This computer has no Wi-Fi" : !Network.wifiEnabled ? "Off" : Network.ssid ? "Connected to " + Network.ssid : "Not connected"
            enabled: Network.available

            ToggleSwitch {
                on: Network.wifiEnabled
                onToggled: Network.setWifi(!Network.wifiEnabled)
            }

            below: [
                NetworkList {
                    Layout.fillWidth: true
                    visible: Network.wifiEnabled
                }
            ]
        }
    }

    CpSection {
        title: "Other connections"

        CpRow {
            glyph: "network-wired-symbolic"
            label: "Ethernet"
            hint: !Network.wiredDevice ? "No network socket" : Network.wired ? "Connected" : "No cable plugged in"
        }

        CpRow {
            glyph: "airplane-mode-symbolic"
            label: "Aeroplane mode"
            hint: "Turns off Wi-Fi and Bluetooth"

            ToggleSwitch {
                on: Network.airplane
                onToggled: Network.setAirplane(!Network.airplane)
            }
        }

        CpRow {
            glyph: "network-vpn-symbolic"
            label: "VPN, fixed addresses and more"
            hint: "Add a VPN, or set an address, proxy or DNS by hand"
            opens: true
            onClicked: Network.openAdvanced()
        }
    }
}
