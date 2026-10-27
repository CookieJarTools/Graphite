// Text in the shell's body style; callers change size, weight or colour where needed.
import QtQuick
import qs.config

Text {
    color: Theme.ink
    font.family: Theme.fontSans
    font.pixelSize: Theme.bodySize
    font.weight: Theme.bodyWeight
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
