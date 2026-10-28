// The Graphite backdrop: its colour and the soft glow (an ellipse 1400 x 960 centred at
// 50% / 40%, fading out by 65% of its reach, as home.css draws it on Windows), filling its
// parent. The desktop, the login screen and the lock screen all stand on it.
import QtQuick
import QtQuick.Shapes
import qs.config

Rectangle {
    id: root

    // How far the glow reaches (1 as drawn; the sign-in screen widens it on the right password).
    property real spread: 1

    color: Theme.backdrop

    Shape {
        anchors.fill: parent
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height * 0.4
            yScale: 960 / 1400
        }

        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height * 0.4
                centerRadius: 700 * Math.SQRT2 * 0.65 * root.spread
                focalX: centerX
                focalY: centerY

                GradientStop { position: 0; color: Theme.backdropGlow }
                GradientStop { position: 1; color: Theme.backdrop }
            }

            startX: 0
            startY: -root.height
            PathLine { x: root.width; y: -root.height }
            PathLine { x: root.width; y: root.height * 2 }
            PathLine { x: 0; y: root.height * 2 }
            PathLine { x: 0; y: -root.height }
        }
    }
}
