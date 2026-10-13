//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root
    visible: true
    title: Translation.tr("Draw")
    minimumWidth: 900
    minimumHeight: 700
    maximumWidth: 900
    maximumHeight: 700
    width: 900
    height: 700
    color: Appearance.m3colors.m3background

    Component.onCompleted: MaterialThemeLoader.reapplyTheme();
    onClosing: Qt.quit()

    readonly property var colorPalette: ["#000000", "#e53935", "#1e88e5", "#43a047", "#fdd835"]
    property color penColor: colorPalette[0]
    property bool erasing: false
    property real penWidth: 5
    property var strokes: []
    property int strokeCursor: 0

    function redrawAll() {
        const ctx = canvas.getContext("2d");
        ctx.fillStyle = "white";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        for (let i = 0; i < root.strokeCursor; i++) {
            const s = root.strokes[i];
            if (!s) continue;
            if (s.type === "clear") {
                ctx.fillStyle = "white";
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                continue;
            }
            if (!s.points || s.points.length < 2) continue;
            ctx.lineWidth = s.width;
            ctx.strokeStyle = s.color;
            ctx.beginPath();
            ctx.moveTo(s.points[0].x, s.points[0].y);
            for (let j = 1; j < s.points.length; j++) ctx.lineTo(s.points[j].x, s.points[j].y);
            ctx.stroke();
        }
        canvas.requestPaint();
    }

    function undo() {
        if (root.strokeCursor <= 0) return;
        root.strokeCursor -= 1;
        root.redrawAll();
    }

    function redo() {
        if (root.strokeCursor >= root.strokes.length) return;
        root.strokeCursor += 1;
        root.redrawAll();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.colorPalette
                delegate: RippleButton {
                    required property string modelData
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    toggled: !root.erasing && root.penColor === modelData
                    colBackground: modelData
                    onClicked: { root.erasing = false; root.penColor = modelData; }
                }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                toggled: root.erasing
                contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 18; text: "ink_eraser"; color: Appearance.colors.colOnLayer1 }
                onClicked: root.erasing = true
            }

            RippleButton {
                enabled: root.strokeCursor > 0
                opacity: enabled ? 1 : 0.35
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 18; text: "undo"; color: Appearance.colors.colOnLayer1 }
                onClicked: root.undo()
            }

            RippleButton {
                enabled: root.strokeCursor < root.strokes.length
                opacity: enabled ? 1 : 0.35
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 18; text: "redo"; color: Appearance.colors.colOnLayer1 }
                onClicked: root.redo()
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                contentItem: StyledText { text: Translation.tr("Clear") }
                onClicked: {
                    if (root.strokeCursor < root.strokes.length) root.strokes = root.strokes.slice(0, root.strokeCursor);
                    root.strokes = root.strokes.concat([{ type: "clear" }]);
                    root.strokeCursor = root.strokes.length;
                    root.redrawAll();
                }
            }

            RippleButton {
                contentItem: StyledText { text: Translation.tr("Cancel") }
                onClicked: root.close()
            }

            RippleButton {
                colBackground: Appearance.colors.colPrimaryContainer
                contentItem: StyledText { text: Translation.tr("Save"); color: Appearance.colors.colOnPrimaryContainer }
                onClicked: root.doSave()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "white"
            radius: Appearance.rounding.small

            Canvas {
                id: canvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate
                property real lastX: -1
                property real lastY: -1
                property string bgPath: Quickshell.env("NOTES_DRAW_BG_PATH") || ""

                function drawBackgroundIfReady() {
                    const ctx = getContext("2d");
                    ctx.fillStyle = "white";
                    ctx.fillRect(0, 0, width, height);
                    if (canvas.bgPath.length > 0 && bgLoader.status === Image.Ready) {
                        ctx.drawImage(bgLoader, 0, 0, width, height);
                    }
                    requestPaint();
                }

                onAvailableChanged: {
                    if (available) canvas.drawBackgroundIfReady();
                }

                Image {
                    id: bgLoader
                    visible: false
                    source: canvas.bgPath.length > 0 ? `file://${canvas.bgPath}` : ""
                    onStatusChanged: {
                        if (status === Image.Ready && canvas.available) canvas.drawBackgroundIfReady();
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => {
                        if (root.strokeCursor < root.strokes.length) root.strokes = root.strokes.slice(0, root.strokeCursor);
                        const newStroke = {
                            type: "stroke",
                            color: root.erasing ? "white" : root.penColor,
                            width: root.erasing ? root.penWidth * 3 : root.penWidth,
                            points: [{ x: mouse.x, y: mouse.y }]
                        };
                        root.strokes = root.strokes.concat([newStroke]);
                        canvas.lastX = mouse.x;
                        canvas.lastY = mouse.y;
                    }
                    onPositionChanged: (mouse) => {
                        if (canvas.lastX < 0) return;
                        const ctx = canvas.getContext("2d");
                        const current = root.strokes[root.strokes.length - 1];
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        ctx.lineWidth = current.width;
                        ctx.strokeStyle = current.color;
                        ctx.beginPath();
                        ctx.moveTo(canvas.lastX, canvas.lastY);
                        ctx.lineTo(mouse.x, mouse.y);
                        ctx.stroke();
                        current.points.push({ x: mouse.x, y: mouse.y });
                        canvas.lastX = mouse.x;
                        canvas.lastY = mouse.y;
                        canvas.requestPaint();
                    }
                    onReleased: {
                        canvas.lastX = -1;
                        canvas.lastY = -1;
                        root.strokeCursor = root.strokes.length;
                    }
                }
            }
        }
    }

    function doSave() {
        const tmpPath = Quickshell.env("NOTES_DRAW_TMP_PATH");
        if (!tmpPath) { root.close(); return; }
        const dataUrl = canvas.toDataURL("image/png");
        const commaIndex = dataUrl.indexOf(",");
        const base64Data = dataUrl.substring(commaIndex + 1);
        // toDataURL()/base64 is used instead of Canvas.save() - save() consistently
        // returned false with "No file name specified" regardless of path format
        // (plain path, file:// URL) - a real bug/quirk in this Qt version's Canvas,
        // not something fixable by adjusting the argument. Base64 contains only
        // [A-Za-z0-9+/=], so it's always safe to embed directly inside single quotes.
        saveFileProc.command = ["bash", "-c", `echo '${base64Data}' | base64 -d > '${tmpPath}'`];
        saveFileProc.running = true;
    }

    Process {
        id: saveFileProc
        onExited: root.close()
    }
}
