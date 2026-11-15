// The wallpaper, filling its parent: the base colour, a soft indigo glow from the top centre
// (an ellipse 55% of the width by 45% of the height, gone by 70% of its reach) and a 72 px
// hairline grid that fades out from the upper middle. The desktop, the login screen and the
// lock screen all stand on it. While `live`, the glow drifts slowly from side to side and
// breathes; it pauses where it is when `live` goes off.
import QtQuick
import QtQuick.Shapes
import qs.config

Rectangle {
    id: root

    // How far the glow reaches (1 as drawn; the sign-in screen widens it on the right password).
    property real spread: 1
    // The glow's strength at its heart.
    property real strength: Theme.glow.a
    property bool live: false

    // -1 to 1: where the glow has drifted to; 0 to 1: how far into a breath it is. Moved only
    // by transform and opacity, which cost the graphics card next to nothing.
    property real drift: 0
    property real breath: 1
    SequentialAnimation on drift {
        running: true
        paused: !root.live
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 14000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: -1; duration: 28000; easing.type: Easing.InOutSine }
        NumberAnimation { from: -1; to: 0; duration: 14000; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on breath {
        running: true
        paused: !root.live
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.72; duration: 9000; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.72; to: 1; duration: 9000; easing.type: Easing.InOutSine }
    }

    color: Theme.wallpaper

    // The glow: a circle's gradient, squashed into the ellipse.
    Shape {
        width: parent.width
        height: parent.height
        x: root.drift * root.width * 0.08
        opacity: root.breath
        readonly property real across: root.width * 0.55 * root.spread
        readonly property real down: root.height * 0.45 * root.spread
        transform: Scale {
            origin.x: root.width / 2
            origin.y: 0
            yScale: parent.across > 0 ? parent.down / parent.across : 1
        }

        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: 0
                centerRadius: Math.max(1, root.width * 0.55 * root.spread)
                focalX: centerX
                focalY: centerY

                GradientStop { position: 0; color: Qt.rgba(Theme.glow.r, Theme.glow.g, Theme.glow.b, root.strength) }
                GradientStop { position: 0.35; color: Qt.rgba(Theme.glow.r, Theme.glow.g, Theme.glow.b, root.strength * 0.45) }
                GradientStop { position: 0.7; color: Qt.rgba(Theme.glow.r, Theme.glow.g, Theme.glow.b, 0) }
            }

            startX: 0
            startY: -root.height * 4
            PathLine { x: root.width; y: -root.height * 4 }
            PathLine { x: root.width; y: root.height * 4 }
            PathLine { x: 0; y: root.height * 4 }
            PathLine { x: 0; y: -root.height * 4 }
        }
    }

    // The grid, drawn once per size: hairlines every 72 px, then kept only where an ellipse
    // around the upper middle lets them through, fading to nothing at its edge.
    Canvas {
        id: grid
        anchors.fill: parent
        readonly property color lineColour: Theme.gridLine
        onLineColourChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        renderStrategy: Canvas.Cooperative

        onPaint: {
            const context = getContext("2d");
            context.reset();
            if (width <= 0 || height <= 0) return;
            context.globalCompositeOperation = "source-over";
            context.strokeStyle = lineColour;
            context.lineWidth = 1;
            context.beginPath();
            for (let x = 72; x < width; x += 72) {
                context.moveTo(Math.round(x) + 0.5, 0);
                context.lineTo(Math.round(x) + 0.5, height);
            }
            for (let y = 72; y < height; y += 72) {
                context.moveTo(0, Math.round(y) + 0.5);
                context.lineTo(width, Math.round(y) + 0.5);
            }
            context.stroke();

            // The fade: an ellipse 60% wide and 70% high at 50% / 25%.
            const across = width * 0.6;
            const down = height * 0.7;
            context.globalCompositeOperation = "destination-in";
            context.save();
            context.translate(width / 2, height * 0.25);
            context.scale(1, down / across);
            const fade = context.createRadialGradient(0, 0, 0, 0, 0, across);
            fade.addColorStop(0, "rgba(0, 0, 0, 1)");
            fade.addColorStop(0.45, "rgba(0, 0, 0, 0.55)");
            fade.addColorStop(1, "rgba(0, 0, 0, 0)");
            context.fillStyle = fade;
            // Well past the screen's edges: only what is filled is faded.
            context.fillRect(-across * 2, -across * 2, across * 4, across * 4);
            context.restore();
        }
    }
}
