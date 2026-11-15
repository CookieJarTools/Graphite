// A minute's line graph for the task manager (TaskManager.qml): the last 30 samples, filled
// beneath; with a faint grid when large.
import QtQuick
import qs.config

Canvas {
    id: graph
    property var points: []
    property color colour: Theme.accent
    property bool small: false
    onPointsChanged: requestPaint()
    onColourChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const context = getContext("2d");
        context.reset();
        const tint = (alpha) => Qt.rgba(graph.colour.r, graph.colour.g, graph.colour.b, alpha);
        context.strokeStyle = graph.small ? tint(0.3) : Theme.cardBorder;
        context.lineWidth = 1;
        context.strokeRect(0.5, 0.5, width - 1, height - 1);
        if (!graph.small) {
            context.strokeStyle = Theme.divider;
            context.beginPath();
            for (let row = 1; row < 4; row++) {
                const y = Math.round(height * row / 4) + 0.5;
                context.moveTo(1, y);
                context.lineTo(width - 1, y);
            }
            for (let column = 1; column < 6; column++) {
                const x = Math.round(width * column / 6) + 0.5;
                context.moveTo(x, 1);
                context.lineTo(x, height - 1);
            }
            context.stroke();
        }
        const points = (graph.points || []).slice(-30);
        if (points.length < 2) return;
        const step = (width - 2) / 29;
        const x = index => width - 1 - (points.length - 1 - index) * step;
        const y = value => height - 1 - value * (height - 2);
        context.beginPath();
        context.moveTo(x(0), height - 1);
        points.forEach((value, index) => context.lineTo(x(index), y(value)));
        context.lineTo(x(points.length - 1), height - 1);
        context.closePath();
        context.fillStyle = tint(0.16);
        context.fill();
        context.beginPath();
        points.forEach((value, index) => index ? context.lineTo(x(index), y(value)) : context.moveTo(x(index), y(value)));
        context.strokeStyle = graph.colour;
        context.lineWidth = graph.small ? 1.5 : 2;
        context.stroke();
    }
}
