import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        id: wallpaperPickerLoader
        active: GlobalStates.wallpaperPickerOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperPicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            // Sized via the shared fractions in GlobalStates so this panel and any
            // future ones (installer, etc.) can be resized together from one place.
            implicitHeight: panelWindow.screen ? panelWindow.screen.height * GlobalStates.panelHeightFraction : 650
            implicitWidth: panelWindow.screen ? panelWindow.screen.width * GlobalStates.panelWidthFraction : 900

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.wallpaperPickerOpen = false;
                }
            }

            WallpaperPickerContent {
                id: content
                anchors {
                    fill: parent
                }
            }
        }
    }

    // HyprGlass: switch it on at login (when it was left on) and keep the tint following the wallpaper while Auto is on
    Process {
        id: glassInitProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/hyprglass_ctl.py", "startup"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    GlobalStates.hyprglassAuto = j.auto === true
                    if (j.message) console.log("[HyprGlass]", j.message)
                } catch (e) {}
            }
        }
    }
    property bool glassTickPending: false
    Process {
        id: glassTickProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/hyprglass_ctl.py", "tick"]
        onExited: { if (root.glassTickPending) { root.glassTickPending = false; glassTickProc.running = true } }
    }
    Timer {
        interval: 15000
        repeat: true
        running: GlobalStates.hyprglassAuto
        onTriggered: { if (!glassTickProc.running) glassTickProc.running = true }
    }
    // ii writes the new path into its config the moment a wallpaper is applied, so follow that instead of waiting for the poll
    FileView {
        path: Quickshell.env("HOME") + "/.config/illogical-impulse/config.json"
        watchChanges: GlobalStates.hyprglassAuto
        onFileChanged: glassTickDelay.restart()
    }
    Timer {
        id: glassTickDelay
        interval: 250
        onTriggered: { if (glassTickProc.running) root.glassTickPending = true; else glassTickProc.running = true }
    }
    Component.onCompleted: glassInitProc.running = true

    // A Hyprland config reload (ii triggers one on every wallpaper change) resets HyprGlass to its defaults, so put the saved look back
    property bool glassReapplyPending: false
    Process {
        id: glassReapplyProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/hyprglass_ctl.py", "reapply"]
        onExited: { if (root.glassReapplyPending) { root.glassReapplyPending = false; glassReapplyProc.running = true } }
    }
    Timer {
        id: glassReapplyDelay
        interval: 400
        onTriggered: { if (glassReapplyProc.running) root.glassReapplyPending = true; else glassReapplyProc.running = true }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") glassReapplyDelay.restart() }
    }

    function toggleWallpaperPicker() {
        GlobalStates.wallpaperPickerOpen = !GlobalStates.wallpaperPickerOpen
    }

    IpcHandler {
        target: "wallpaperPicker"

        function toggle(): void {
            root.toggleWallpaperPicker();
        }

        function open(): void {
            GlobalStates.wallpaperPickerOpen = true;
        }
    }

    GlobalShortcut {
        name: "wallpaperPickerToggle"
        description: "Toggle custom wallpaper picker"
        onPressed: {
            root.toggleWallpaperPicker();
        }
    }
}
