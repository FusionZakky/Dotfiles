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
        id: packageInstallerLoader
        active: GlobalStates.packageInstallerOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:packageInstaller"
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

            implicitHeight: panelWindow.screen ? panelWindow.screen.height * 0.75 : 650
            implicitWidth: panelWindow.screen ? panelWindow.screen.width * 0.7 : 900

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.packageInstallerOpen = false;
                }
            }

            PackageInstallerContent {
                id: content
                anchors {
                    fill: parent
                }
            }
        }
    }

    function togglePackageInstaller() {
        GlobalStates.packageInstallerOpen = !GlobalStates.packageInstallerOpen
    }

    IpcHandler {
        target: "packageInstaller"

        function toggle(): void {
            root.togglePackageInstaller();
        }
    }

    GlobalShortcut {
        name: "packageInstallerToggle"
        description: "Toggle package installer"
        onPressed: {
            root.togglePackageInstaller();
        }
    }
}
