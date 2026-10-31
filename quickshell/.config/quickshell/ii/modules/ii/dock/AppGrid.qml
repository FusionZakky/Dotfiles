import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * Touch app launcher for tablet mode: tap an app to open it, tap the search box to type (the keyboard
 * opens with it). "Edit" turns taps into pin/unpin for the shelf; press-and-hold on an app does the same
 * without switching modes. Loaded only while tablet mode is on and closed when it ends.
 */
Scope {
    id: root

    readonly property bool open: TabletMode.gridOpen
    property bool editing: false
    property string query: ""

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        return Array.from(DesktopEntries.applications.values)
            .filter(a => !a.noDisplay && (q === "" || a.name.toLowerCase().includes(q)))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    function isPinned(id: string): bool {
        const list = Config.options.dock.pinnedApps || [];
        return list.some(s => s.toLowerCase() === id.toLowerCase());
    }

    function togglePin(id: string): void {
        const cur = Array.from(Config.options.dock.pinnedApps || []);
        const i = cur.findIndex(s => s.toLowerCase() === id.toLowerCase());
        if (i >= 0) cur.splice(i, 1);
        else cur.push(id);
        Config.options.dock.pinnedApps = cur;
    }

    onOpenChanged: {
        if (!root.open) {
            root.editing = false;
            root.query = "";
            GlobalStates.oskOpen = false;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // leave the shelf (and its buttons) uncovered underneath
            margins.bottom: 78 + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:tabletAppGrid"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            MouseArea { // tap outside the panel to close
                anchors.fill: parent
                onClicked: TabletMode.gridOpen = false
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 1100)
                height: parent.height - 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                MouseArea { anchors.fill: parent } // taps on the panel itself must not close it

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle { // search box
                            Layout.fillWidth: true
                            implicitHeight: 56
                            radius: height / 2
                            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.08)

                            MaterialSymbol {
                                id: searchIcon
                                anchors.left: parent.left
                                anchors.leftMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 26
                                text: "search"
                                color: Appearance.colors.colOnLayer0
                            }
                            TextInput {
                                id: field
                                anchors.left: searchIcon.right
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 18
                                anchors.verticalCenter: parent.verticalCenter
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.larger
                                clip: true
                                onTextChanged: root.query = text
                                onActiveFocusChanged: if (activeFocus) GlobalStates.oskOpen = true

                                Text {
                                    visible: field.text.length === 0
                                    text: "Search apps"
                                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.5)
                                    font: field.font
                                }
                                Connections {
                                    target: root
                                    function onQueryChanged() {
                                        if (field.text !== root.query) field.text = root.query;
                                    }
                                }
                            }
                        }

                        Rectangle { // edit toggle
                            implicitWidth: editRow.implicitWidth + 36
                            implicitHeight: 56
                            radius: height / 2
                            color: root.editing ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.colors.colOnLayer0, 0.08)

                            Row {
                                id: editRow
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.pixelSize: 24
                                    text: root.editing ? "check" : "edit"
                                    color: root.editing ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.editing ? "Done" : "Edit shelf"
                                    font.pixelSize: 16
                                    color: root.editing ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.editing = !root.editing
                            }
                        }
                    }

                    Text {
                        visible: root.editing
                        Layout.fillWidth: true
                        text: "Tap an app to add it to, or remove it from, the shelf."
                        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.7)
                        font.pixelSize: 15
                    }

                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        readonly property int columns: Math.max(3, Math.floor(width / 150))
                        cellWidth: Math.floor(width / columns)
                        cellHeight: 150
                        model: root.filtered

                        delegate: Item {
                            id: cell
                            required property var modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            property bool pinned: root.isPinned(cell.modelData.id)

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 72
                                    implicitHeight: 72

                                    Image {
                                        anchors.fill: parent
                                        source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                                        sourceSize: Qt.size(144, 144)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Rectangle { // add/remove badge, only while editing
                                        visible: root.editing
                                        width: 30
                                        height: 30
                                        radius: 15
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: -8
                                        anchors.rightMargin: -8
                                        color: cell.pinned ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            font.pixelSize: 20
                                            text: cell.pinned ? "check" : "add"
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                }
                                Text {
                                    Layout.preferredWidth: cell.width - 16
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    text: cell.modelData.name
                                    color: Appearance.colors.colOnLayer0
                                    font.pixelSize: 14
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.editing) {
                                        root.togglePin(cell.modelData.id);
                                    } else {
                                        cell.modelData.execute();
                                        TabletMode.gridOpen = false;
                                    }
                                }
                                onPressAndHold: root.togglePin(cell.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
