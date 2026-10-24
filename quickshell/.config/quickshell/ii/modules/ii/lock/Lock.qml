pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})
    property bool previewActive: false
    // Workspace slide speed during a preview, in tenths of a second. set-lock-hold keeps this about 0.2s under the hold time.
    property real previewSpeed: 9.5

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            var batch = ""
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${monName}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${wsId}})';`
                }
            }
            if (batch.length > 0) {
                Quickshell.execDetached(["bash", "-c", batch])
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                if (root.previewActive) {
                    // Already on the temp workspace from the hold preview: keep it
                    root.previewActive = false
                    previewFailsafe.stop()
                    return
                }
                var next = {}
                var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    if (mData?.activeWorkspace == undefined) {
                        return;
                    }
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["bash", "-c", batch])
            } else {
                restoreTimer.start()
            }
        }
    }

    // Hold-to-lock preview: when the lock key is held, start the same workspace slide-away a real lock does, and
    // slide back if it is released before the lock fires. The delay ignores quick taps; the failsafe puts
    // everything back if the lock never arrives.
    // Slow (or restore) the workspace slide. The normal values mirror hypr/hyprland/general.lua.
    function setSlideSpeed(slow) {
        var lua = slow
            ? `(function() pcall(hl.curve, "lockPreview", { type = "bezier", points = {{0.4, 0}, {0.2, 1}} }); hl.animation({ leaf = "workspaces", enabled = true, speed = ${root.previewSpeed}, bezier = "lockPreview", style = "slide" }) end)()`
            : `hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slide" })`
        Quickshell.execDetached(["hyprctl", "eval", lua])
    }

    Timer {
        id: animResetTimer
        interval: 1600
        repeat: false
        onTriggered: {
            root.setSlideSpeed(false)
            root.setBlurFade(false)
            GlobalStates.lockPreviewMs = 400
        }
    }

    // Slow (or restore) the layer fade-in so the blur layer's blur ramps in over the preview. Normal values mirror general.lua.
    function setBlurFade(slow) {
        var lua = slow
            ? `(function() pcall(hl.curve, "lockPreview", { type = "bezier", points = {{0.4, 0}, {0.2, 1}} }); hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = ${root.previewSpeed}, bezier = "lockPreview" }) end)()`
            : `hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 0.5, bezier = "menu_decel" })`
        Quickshell.execDetached(["hyprctl", "eval", lua])
    }

    function startPreview() {
        if (GlobalStates.screenLocked || root.previewActive || !GlobalStates.lockPreview) return
        var next = {}
        var batch = ""
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var mon = Quickshell.screens[i].name
            var mData = HyprlandData.monitors.find(m => m.name === mon)
            if (mData?.activeWorkspace == undefined) return
            var ws = (mData?.activeWorkspace?.id ?? 1)
            next[mon] = ws
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})';`
        }
        root.savedWorkspaces = next
        root.previewActive = true
        previewFailsafe.restart()
        root.setSlideSpeed(true)
        root.setBlurFade(true)
        GlobalStates.lockPreviewMs = Math.round(root.previewSpeed * 100)
        animResetTimer.restart()
        Quickshell.execDetached(["bash", "-c", batch])
    }

    Timer {
        id: previewDelay
        interval: 250
        repeat: false
        onTriggered: root.startPreview()
    }

    Timer {
        id: previewFailsafe
        interval: 2500
        repeat: false
        onTriggered: {
            if (root.previewActive && !GlobalStates.screenLocked) {
                root.previewActive = false
                GlobalStates.lockPreview = false
                restoreTimer.start()
                animResetTimer.restart()
            }
        }
    }

    Connections {
        target: GlobalStates
        function onLockPreviewChanged() {
            if (GlobalStates.lockPreview) {
                previewDelay.restart()
            } else {
                previewDelay.stop()
                if (root.previewActive && !GlobalStates.screenLocked) {
                    // Released before the lock fired: slide back
                    root.previewActive = false
                    previewFailsafe.stop()
                    restoreTimer.start()
                    animResetTimer.restart()
                }
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: blurScope
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2

            // Blurs everything behind it, windows included, while a lock preview runs. Its blur follows the layer
            // fade-in, which setBlurFade() slows to the preview length (rules: hypr/hyprland/rules.lua, quickshell:lockBlur).
            LazyLoader {
                active: root.previewActive
                component: PanelWindow {
                    screen: blurScope.modelData
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "quickshell:lockBlur"
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    mask: Region {}

                    Rectangle {
                        anchors.fill: parent
                        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.98)
                    }
                }
            }
        }
    }
}
