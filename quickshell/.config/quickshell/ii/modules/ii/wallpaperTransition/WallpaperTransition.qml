pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common

/**
 * Wallpaper reveal transition.
 *
 * Flow (driven from switchwall.sh through IPC, so every way of changing the wallpaper gets it):
 *   1. switchwall.sh screenshots every monitor to /tmp/wp-transition and calls `wpTransition begin`.
 *   2. This overlay shows the screenshot full-screen (looks identical to the live screen) and
 *      touches <stamp>.ready so the script knows it may start changing things underneath.
 *   3. When the script exits it calls `wpTransition end`; after a short settle delay a circle
 *      grows from the cursor, showing the live, fully updated screen through the hole.
 *   4. The overlay hides itself and deletes its screenshots.
 * It only ever looks at pixels, so it does not care what widgets, tabs or modules exist.
 * Tunables: Config.options.background.transition.*
 */
Scope {
    id: root

    readonly property var cfg: Config.options.background.transition
    readonly property string dir: "/tmp/wp-transition"

    property bool active: false
    property string stamp: ""
    property real cursorX: 0
    property real cursorY: 0
    property real progress: 0
    property int imagesSettled: 0

    IpcHandler {
        target: "wpTransition"
        function begin(x: int, y: int, stamp: string): string {
            if (!root.cfg.enable) return "off";
            root.start(x, y, stamp);
            return "ok";
        }
        function end(): void {
            root.release();
        }
    }

    function start(x, y, newStamp) {
        revealAnim.stop();
        settleTimer.stop();
        readyTimer.stop();
        root.cursorX = x;
        root.cursorY = y;
        root.progress = 0;
        root.imagesSettled = 0;
        root.stamp = newStamp;
        root.active = true;
        failsafe.interval = root.cfg.timeoutMs;
        failsafe.restart();
    }

    // Called when switchwall.sh has exited: give the shell a moment to finish recolouring
    function release() {
        if (!root.active) return;
        settleTimer.interval = root.cfg.settleMs;
        settleTimer.restart();
    }

    function reveal() {
        failsafe.stop();
        settleTimer.stop();
        if (!root.active || revealAnim.running) return;
        Quickshell.execDetached(["bash", "-c", "printf '%s %s\\n' reveal $EPOCHREALTIME >> /tmp/wp-timing.log"]); // WPTIMING
        revealAnim.duration = root.cfg.durationMs;
        revealAnim.restart();
    }

    function finish() {
        const old = root.stamp;
        root.active = false;
        root.progress = 0;
        cleanupProc.command = ["bash", "-c", `rm -f ${root.dir}/${old}-*.ppm ${root.dir}/${old}.ready`];
        cleanupProc.running = true;
    }

    function imageSettled() {
        root.imagesSettled++;
        if (root.imagesSettled >= Quickshell.screens.length) readyTimer.restart();
    }

    Timer { id: settleTimer; onTriggered: root.reveal() }
    // Never leave a frozen screen behind if the script dies before reporting back
    Timer { id: failsafe; onTriggered: root.reveal() }
    // Small delay so the overlay has really been painted before the script is told to go ahead
    Timer { id: readyTimer; interval: 60; onTriggered: { readyProc.command = ["touch", `${root.dir}/${root.stamp}.ready`]; readyProc.running = true } }
    Process { id: readyProc }
    Process { id: cleanupProc }

    NumberAnimation {
        id: revealAnim
        target: root
        property: "progress"
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
        onFinished: root.finish()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:wallpaperTransition"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {} // click-through: the overlay never eats input

            readonly property real localX: root.cursorX - modelData.x
            readonly property real localY: root.cursorY - modelData.y
            // Distance to the farthest corner, so the circle always ends up covering the whole screen
            readonly property real maxRadius: Math.max(
                Math.hypot(localX, localY),
                Math.hypot(width - localX, localY),
                Math.hypot(localX, height - localY),
                Math.hypot(width - localX, height - localY))

            Image {
                id: shot
                anchors.fill: parent
                visible: false
                cache: false
                asynchronous: true
                source: (root.active && root.stamp !== "") ? `file://${root.dir}/${root.stamp}-${win.modelData.name}.ppm` : ""
                onStatusChanged: if (status === Image.Ready || status === Image.Error) root.imageSettled()
            }

            ShaderEffect {
                anchors.fill: parent
                property variant src: shot
                property vector2d center: Qt.vector2d(win.localX, win.localY)
                property vector2d size: Qt.vector2d(win.width, win.height)
                property real radius: root.progress * (win.maxRadius + root.cfg.featherPx)
                property real feather: root.cfg.featherPx
                fragmentShader: Qt.resolvedUrl("reveal.frag.qsb")
            }
        }
    }
}
