// A group of Control Panel rows under a small heading.
import QtQuick
import QtQuick.Layouts
import qs.config

ColumnLayout {
    id: root

    property string title
    default property alias rows: list.data

    Layout.fillWidth: true
    Layout.topMargin: Theme.space4
    spacing: Theme.space1

    UiText {
        visible: root.title.length > 0
        Layout.bottomMargin: Theme.space1
        text: root.title
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    ColumnLayout {
        id: list
        Layout.fillWidth: true
        spacing: Theme.space1
    }
}
