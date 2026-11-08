// Mouse-wheel scrolling at a usable pace, for the Flickable (or list) it's put in: Qt's own goes
// by the few pixels Wayland gives a wheel notch, so a long page took dozens of turns. A notch
// glides `step` pixels, and quick turns add up. It lies over the view (clicks and hovering pass
// through); touchpads keep Qt's own scrolling, which follows the fingers.
import QtQuick

MouseArea {
    id: root

    required property Flickable flickable
    property real step: 160

    parent: flickable
    anchors.fill: parent
    z: 1
    acceptedButtons: Qt.NoButton

    function clamped(y) {
        return Math.max(flickable.originY, Math.min(flickable.originY + Math.max(0, flickable.contentHeight - flickable.height), y));
    }

    // A wheel's steps: whole notches (120), or a smooth wheel's eighths of one, most without a
    // pixel distance; a touchpad gives a pixel distance every time. Once a step without one has
    // come, the next second's are the wheel's too.
    property double wheelUntil: 0

    onWheel: wheel => {
        const now = Date.now();
        if (wheel.angleDelta.y !== 0 && wheel.pixelDelta.y === 0) wheelUntil = now + 1000;
        const isWheel = wheel.angleDelta.y !== 0 && (wheel.pixelDelta.y === 0 || wheel.angleDelta.y % 120 === 0 || now < wheelUntil);
        if (!isWheel) {
            wheel.accepted = false;
            return;
        }
        // Qt's own glide (from a step it had) would take over from this one.
        flickable.cancelFlick();
        const to = clamped((glide.running ? glide.to : flickable.contentY) - wheel.angleDelta.y / 120 * step);
        glide.stop();
        glide.to = to;
        glide.start();
    }

    NumberAnimation {
        id: glide
        target: root.flickable
        property: "contentY"
        duration: 140
        easing.type: Easing.OutCubic
    }
}
