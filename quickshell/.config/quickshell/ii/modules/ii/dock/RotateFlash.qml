import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common

/**
 * Short fade-through-black when the screen rotates in tablet mode. Loaded only while tablet mode is on,
 * and the window itself only exists while the fade is running; it never takes input.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: flashWindow
            required property var modelData
            screen: modelData
            visible: veil.opacity > 0.01

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:tabletRotateFlash"
            color: "transparent"
            mask: Region {}

            Rectangle {
                id: veil
                anchors.fill: parent
                color: "black"
                opacity: 0
            }

            Connections {
                target: TabletMode
                function onRotationsChanged() {
                    flash.restart();
                }
            }

            SequentialAnimation {
                id: flash
                NumberAnimation { target: veil; property: "opacity"; to: 0.92; duration: 90; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 260 }
                NumberAnimation { target: veil; property: "opacity"; to: 0; duration: 320; easing.type: Easing.InOutQuad }
            }
        }
    }
}
