// A group of Control Panel rows under a small heading. Its rows join into one card (each row
// draws its part of it, CpRow.qml); anything else put in the group sits between cards.
import QtQuick
import QtQuick.Layouts
import qs.config

ColumnLayout {
    id: root

    property string title
    default property alias rows: list.data

    Layout.fillWidth: true
    Layout.topMargin: Theme.space6
    spacing: Theme.space2

    UiText {
        visible: root.title.length > 0
        Layout.leftMargin: 2
        text: root.title
        color: Theme.inkFaint
        font.pixelSize: Theme.sectionSize
        font.weight: Theme.labelWeight
    }

    ColumnLayout {
        id: list
        Layout.fillWidth: true
        spacing: 0
    }
}
