// A one-line text field in a box, with a greyed hint while empty; `password` hides what is
// typed, and Enter sends accepted().
import QtQuick
import qs.config

Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property bool password: false
    signal accepted()

    function focusField() {
        input.forceActiveFocus();
    }

    implicitWidth: 200
    implicitHeight: 36
    radius: Theme.radiusSm
    color: Theme.surface100
    border.color: input.activeFocus ? Theme.accent : Theme.line
    border.width: 1

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "●"
        color: Theme.ink
        selectionColor: Theme.accentSoft
        font.family: Theme.fontSans
        font.pixelSize: Theme.bodySize
        activeFocusOnTab: true
        clip: true
        Keys.onReturnPressed: root.accepted()
        Keys.onEnterPressed: root.accepted()

        UiText {
            anchors.fill: parent
            visible: input.text.length === 0
            text: root.placeholder
            color: Theme.inkMuted
        }
    }
}
