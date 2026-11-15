// One row of a Control Panel page, at least 56 px: a name (and a line of explanation under
// it), and its control on the right (a switch, a button, a choice; whatever is put inside).
// With `opens`, the whole row is a button (clicked()); `below` holds anything that hangs under
// it (a list, a form). It leads with a symbolic `glyph`, or an app's `icon` in its own colours.
// Rows next to each other make one card, a hairline between each; a row draws its own part:
// rounded at the top when nothing row-like is above it, at the bottom when nothing is below.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config

Item {
    id: root

    property string label
    property string hint
    property string glyph
    property string icon
    property bool opens: false
    default property alias control: controls.data
    property alias below: belowArea.data
    signal clicked()

    // How its neighbours tell it is a row.
    readonly property bool isCpRow: true

    // The visible things just before and after it in its group (a Repeater itself is skipped:
    // its rows stand in its place).
    readonly property var neighbours: {
        const kids = parent ? parent.children : [];
        let before = null;
        let after = null;
        let seen = false;
        for (let index = 0; index < kids.length; index++) {
            const kid = kids[index];
            if (kid === root) {
                seen = true;
                continue;
            }
            if (!kid.visible || typeof kid.itemAt === "function") continue;
            if (!seen) before = kid;
            else {
                after = kid;
                break;
            }
        }
        return { before: before, after: after };
    }
    readonly property bool joinedAbove: !!neighbours.before && neighbours.before.isCpRow === true
    readonly property bool joinedBelow: !!neighbours.after && neighbours.after.isCpRow === true

    Layout.fillWidth: true
    Layout.topMargin: neighbours.before && !joinedAbove ? Theme.space2 : 0
    Layout.bottomMargin: neighbours.after && !joinedBelow ? Theme.space2 : 0
    implicitHeight: Math.max(56, column.implicitHeight + Theme.space3 * 2)
    opacity: enabled ? 1 : 0.5

    Accessible.role: opens ? Accessible.Button : Accessible.Grouping
    Accessible.name: label
    Accessible.description: hint
    Accessible.onPressAction: if (root.opens) root.clicked()

    // Its part of the card: a rounded card reaching past the row's joined edges, cut to the row.
    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            readonly property real reach: Theme.radiusCard * 2
            y: root.joinedAbove ? -reach : 0
            width: parent.width
            height: parent.height + (root.joinedAbove ? reach : 0) + (root.joinedBelow ? reach : 0)
            radius: Theme.radiusCard
            color: Theme.cardFill
            border.color: Theme.cardBorder
            border.width: 1

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: root.opens && mouse.containsMouse ? Theme.hoverRow : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
            }
        }
    }

    // The hairline from the row above.
    Rectangle {
        visible: root.joinedAbove
        x: Theme.space4
        width: parent.width - Theme.space4 * 2
        height: 1
        color: Theme.divider
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.opens
        enabled: root.opens
        cursorShape: root.opens ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: column
        x: Theme.space4
        y: Theme.space3
        width: parent.width - Theme.space4 * 2
        spacing: Theme.space3

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 32
            spacing: Theme.space3

            Glyph {
                visible: root.glyph.length > 0 && root.icon.length === 0
                name: root.glyph
                tint: Theme.inkMuted
            }

            IconImage {
                visible: root.icon.length > 0
                implicitSize: 28
                source: root.icon ? Quickshell.iconPath(root.icon, "application-x-executable") : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                UiText {
                    Layout.fillWidth: true
                    text: root.label
                    font.pixelSize: Theme.labelSize
                    font.weight: Theme.labelWeight
                }

                UiText {
                    Layout.fillWidth: true
                    visible: root.hint.length > 0
                    text: root.hint
                    color: Theme.inkFaint
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }

            RowLayout {
                id: controls
                spacing: Theme.space2
            }

            Glyph {
                visible: root.opens
                name: "go-next-symbolic"
                implicitSize: 14
                tint: Theme.inkFaint
            }
        }

        ColumnLayout {
            id: belowArea
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: Theme.space2
        }
    }
}
