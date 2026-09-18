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

    function toggleWallpaperPicker() {
        GlobalStates.wallpaperPickerOpen = !GlobalStates.wallpaperPickerOpen
    }

    IpcHandler {
        target: "wallpaperPicker"

        function toggle(): void {
            root.toggleWallpaperPicker();
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
