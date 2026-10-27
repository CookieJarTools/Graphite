// A 16 px symbolic icon from the icon theme (Papirus-Dark, set in shell.qml).
import QtQuick
import Quickshell
import Quickshell.Widgets

IconImage {
    property string name
    implicitSize: 16
    source: Quickshell.iconPath(name, "image-missing")
}
