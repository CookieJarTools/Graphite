// A 16 px icon in the text colour (or `tint`): one of the shell's own outline icons
// (assets/icons, Theme.iconFor) where there is one, else a symbolic icon from the icon theme
// (Papirus-Dark, set in shell.qml), tinted too: some symbolic icons exist only in Papirus'
// dark-on-light set and would vanish on the dark surfaces otherwise.
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
    readonly property url drawn: Theme.iconFor(name)

    implicitSize: 16
    source: drawn.toString() ? drawn : Quickshell.iconPath(name, "image-missing")

    layer.enabled: symbolic || drawn.toString() !== ""
    layer.effect: MultiEffect {
        brightness: 1
        colorization: 1
        colorizationColor: glyph.tint
    }
}
