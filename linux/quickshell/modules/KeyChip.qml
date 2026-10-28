// A key, as in "Super E" or "Alt 1": a small raised label.
import QtQuick
import qs.config

Rectangle {
    property alias text: label.text

    implicitWidth: Math.max(Theme.keyHeight, label.implicitWidth + Theme.space2 * 2)
    implicitHeight: Theme.keyHeight
    radius: 4
    color: Theme.key
    border.color: Theme.lineStrong
    border.width: 1

    UiText {
        id: label
        anchors.centerIn: parent
        color: Theme.inkMuted
        font.family: Theme.fontMono
        font.pixelSize: Theme.keySize
    }
}
