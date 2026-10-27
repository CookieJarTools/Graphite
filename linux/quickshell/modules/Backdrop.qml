// The desktop itself: the Graphite backdrop (its colour and the soft glow, as Home draws them
// on Windows) on the background layer of each screen, under every window. No wallpaper.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.config

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.backdrop
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "graphite-backdrop"

    // The glow: an ellipse 1400 x 960 centred at 50% / 40%, fading out by 65% of its reach
    // (home.css), drawn as a circle squashed vertically.
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
                centerRadius: 700 * Math.SQRT2 * 0.65
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
