// A 16 px symbolic icon from the icon theme (Papirus-Dark, set in shell.qml), drawn in the
// text colour: some symbolic icons exist only in Papirus' dark-on-light set and would vanish
// on the dark surfaces otherwise.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config

IconImage {
    id: glyph

    property string name
    property color tint: Theme.ink
    readonly property bool symbolic: name.endsWith("-symbolic")

    implicitSize: 16
    source: Quickshell.iconPath(name, "image-missing")

    layer.enabled: symbolic
    layer.effect: MultiEffect {
        brightness: 1
        colorization: 1
        colorizationColor: glyph.tint
    }
}
