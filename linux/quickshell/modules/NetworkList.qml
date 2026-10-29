// The Wi-Fi networks in range (Network.networks), for quick settings and the Control Panel.
// A click on one opens it: Connect (asking for the password when it has one and isn't saved),
// Disconnect, Forget. A wrong password says so and asks again. "Hidden network" at the end
// joins one by its name. The list scans while it is on screen (Network.watching, set by the
// owner).
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: root

    property string opened: "" // the network whose row is open
    property bool joiningHidden: false

    spacing: 2

    UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        visible: Network.wifiEnabled && Network.networks.length === 0
        text: Network.available ? "Looking for networks..." : "This computer has no Wi-Fi."
        color: Theme.inkMuted
    }

    UiText {
        Layout.fillWidth: true
        visible: !Network.wifiEnabled
        text: "Wi-Fi is off."
        color: Theme.inkMuted
    }

    // The networks' names in order, changed only when the list itself changes, and not at all
    // while one is open: a new scan then rebuilt every row, emptying the password being typed.
    property var shown: []

    function sync() {
        if (opened !== "" && shown.includes(opened)) return;
        const names = Network.networks.map(network => network.name);
        if (names.join("|") !== shown.join("|")) shown = names;
    }

    Connections {
        target: Network
        function onNetworksChanged() { root.sync(); }
    }
    onOpenedChanged: sync()
    Component.onCompleted: sync()

    Repeater {
        model: root.shown

        Rectangle {
            id: row
            required property string modelData // the network's name
            readonly property var net: Network.networks.find(network => network.name === modelData) || ({ name: modelData, connected: false, known: false, signalStrength: 0, stateChanging: false, connectionFailed: false })
            readonly property bool isOpen: root.opened === net.name
            readonly property bool secure: Network.isSecure(net)
            readonly property bool busy: net.stateChanging
            property bool tried: false // a connect pressed here (an old failure of its own says nothing)
            readonly property bool failed: tried && net.connectionFailed && !busy
            property bool askPassword: false // a saved password was refused: ask again
            readonly property bool needsPassword: secure && (!net.known || askPassword)

            Layout.fillWidth: true
            implicitHeight: content.implicitHeight + Theme.space2 * 2
            radius: Theme.radiusSm
            color: isOpen ? Theme.surface100 : rowMouse.containsMouse ? Theme.surface300 : "transparent"

            onFailedChanged: if (failed && secure) {
                askPassword = true;
                root.opened = net.name;
            }

            function connectNow() {
                if (needsPassword && !password.text) {
                    password.focusField();
                    return;
                }
                tried = true;
                Network.connect(net, needsPassword ? password.text : "");
                password.text = "";
                askPassword = false;
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.opened = row.isOpen ? "" : row.net.name;
                    if (row.isOpen && row.needsPassword && !row.net.connected) password.focusField();
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

                    Glyph { name: Network.glyphFor(row.net) }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        UiText {
                            Layout.fillWidth: true
                            text: row.net.name
                            font.weight: row.net.connected ? Font.DemiBold : Font.Normal
                        }

                        UiText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: row.busy ? (row.net.connected ? "Disconnecting..." : "Connecting...")
                                : row.failed ? (row.secure ? "Wrong password. Try again." : "Couldn't connect")
                                : row.net.connected ? "Connected" + (row.secure ? ", secured" : "")
                                : row.net.known ? "Saved" : row.secure ? "" : "Open network"
                            color: row.failed ? Theme.danger : row.net.connected ? Theme.success : Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                    }

                    Glyph {
                        visible: row.secure
                        name: "system-lock-screen-symbolic"
                        opacity: 0.6
                    }
                }

                // Opened: the password (when needed) and the buttons.
                FieldBox {
                    id: password
                    Layout.fillWidth: true
                    visible: row.isOpen && row.needsPassword && !row.net.connected
                    placeholder: "Password"
                    password: true
                    onAccepted: row.connectNow()
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: row.isOpen
                    spacing: Theme.space2

                    Item { Layout.fillWidth: true }

                    PillButton {
                        visible: row.net.known
                        text: "Forget"
                        onClicked: {
                            row.net.forget();
                            root.opened = "";
                        }
                    }

                    PillButton {
                        visible: row.net.connected
                        text: "Disconnect"
                        onClicked: row.net.disconnect()
                    }

                    PillButton {
                        visible: !row.net.connected
                        primary: true
                        enabled: !row.busy
                        text: "Connect"
                        onClicked: row.connectNow()
                    }
                }
            }
        }
    }

    // ---------- a hidden network ----------

    Rectangle {
        Layout.fillWidth: true
        visible: Network.wifiEnabled && Network.available
        implicitHeight: hiddenContent.implicitHeight + Theme.space2 * 2
        radius: Theme.radiusSm
        color: root.joiningHidden ? Theme.surface100 : hiddenMouse.containsMouse ? Theme.surface300 : "transparent"

        MouseArea {
            id: hiddenMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.joiningHidden = !root.joiningHidden;
                Network.hiddenResult = "";
                if (root.joiningHidden) hiddenName.focusField();
            }
        }

        ColumnLayout {
            id: hiddenContent
            x: Theme.space3
            y: Theme.space2
            width: parent.width - Theme.space3 * 2
            spacing: Theme.space2

            RowLayout {
                spacing: Theme.space3
                Glyph { name: "list-add-symbolic" }
                UiText {
                    text: "Hidden network"
                    color: Theme.inkMuted
                }
            }

            FieldBox {
                id: hiddenName
                Layout.fillWidth: true
                visible: root.joiningHidden
                placeholder: "Network name"
                onAccepted: hiddenPassword.focusField()
            }

            FieldBox {
                id: hiddenPassword
                Layout.fillWidth: true
                visible: root.joiningHidden
                placeholder: "Password, if it has one"
                password: true
                onAccepted: join.clicked()
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.joiningHidden
                spacing: Theme.space2

                UiText {
                    Layout.fillWidth: true
                    text: Network.hiddenResult === "joining" ? "Connecting..." : Network.hiddenResult === "ok" ? "Connected" : Network.hiddenResult
                    color: Network.hiddenResult === "ok" ? Theme.success : Network.hiddenResult === "joining" ? Theme.inkMuted : Theme.danger
                    font.pixelSize: Theme.hintSize
                }

                PillButton {
                    id: join
                    primary: true
                    text: "Connect"
                    enabled: hiddenName.text.trim().length > 0 && Network.hiddenResult !== "joining"
                    onClicked: {
                        Network.joinHidden(hiddenName.text.trim(), hiddenPassword.text);
                        hiddenPassword.text = "";
                    }
                }
            }
        }
    }
}
