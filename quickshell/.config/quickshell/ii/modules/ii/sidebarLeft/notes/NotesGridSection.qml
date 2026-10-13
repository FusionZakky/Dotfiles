pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.notes

Item {
    id: root
    required property string section // "archived" | "trash"
    property string openNoteId: ""
    property string zoomImagePath: ""
    property string zoomCacheBust: ""

    StackLayout {
        anchors.fill: parent
        currentIndex: root.openNoteId.length > 0 ? 1 : 0

        Item {
        GridView {
            id: grid
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            readonly property int minCellWidth: 150
            readonly property int columns: Math.max(1, Math.floor(width / minCellWidth))
            cellWidth: width / columns
            cellHeight: 100
            model: root.section === "trash" ? Notes.trashNotes : Notes.archivedNotes
            delegate: Item {
                id: card
                required property var modelData
                property bool showMenu: false
                width: grid.cellWidth
                height: grid.cellHeight

                readonly property bool isPhotoCard: (card.modelData.type === "image" || card.modelData.type === "drawing") && (card.modelData.images ?? []).length > 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Appearance.rounding.small
                    color: (!card.isPhotoCard && card.modelData.color) ? card.modelData.color : Appearance.colors.colLayer2
                    clip: true

                    Image {
                        visible: card.isPhotoCard
                        anchors.fill: parent
                        source: card.isPhotoCard ? `file://${Directories.notesAssetsDir}/${card.modelData.id}/${card.modelData.images[0].filename}?${card.modelData.images[0].addedAt}` : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    ColumnLayout {
                        visible: !card.isPhotoCard
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        StyledText {
                            Layout.fillWidth: true
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            color: (card.modelData.color ? "#1f1f1f" : Appearance.colors.colOnLayer2)
                            text: card.modelData.title
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            elide: Text.ElideRight
                            maximumLineCount: 3
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: (card.modelData.color ? "#3a3a3a" : Appearance.colors.colSubtext)
                            text: card.modelData.preview ?? ""
                        }
                        StyledText {
                            visible: root.section === "trash" && card.modelData.deletedAt
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: (card.modelData.color ? "#3a3a3a" : Appearance.colors.colSubtext)
                            text: {
                                if (!card.modelData.deletedAt) return "";
                                const msRemaining = card.modelData.deletedAt + 30 * 86400000 - Date.now();
                                const daysRemaining = Math.ceil(msRemaining / 86400000);
                                return daysRemaining < 1 ? Translation.tr("Deletes in <1 day") : Translation.tr("Deletes in %1 days").arg(daysRemaining);
                            }
                        }
                    }

                    Rectangle {
                        visible: card.isPhotoCard && root.section === "trash" && card.modelData.deletedAt
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: 4
                        radius: 3
                        color: "#aa000000"
                        implicitWidth: photoDeleteLabel.implicitWidth + 8
                        implicitHeight: photoDeleteLabel.implicitHeight + 4
                        StyledText {
                            id: photoDeleteLabel
                            anchors.centerIn: parent
                            font.pixelSize: 9
                            color: "white"
                            text: {
                                const msRemaining = card.modelData.deletedAt + 30 * 86400000 - Date.now();
                                const daysRemaining = Math.ceil(msRemaining / 86400000);
                                return daysRemaining < 1 ? Translation.tr("<1 day") : Translation.tr("%1 days").arg(daysRemaining);
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.isPhotoCard) {
                                root.zoomImagePath = `${Directories.notesAssetsDir}/${card.modelData.id}/${card.modelData.images[0].filename}`;
                                root.zoomCacheBust = String(card.modelData.images[0].addedAt);
                            } else {
                                root.openNoteId = card.modelData.id;
                            }
                        }
                    }

                    RippleButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        implicitWidth: 24
                        implicitHeight: 24
                        buttonRadius: Appearance.rounding.full
                        onClicked: card.showMenu = !card.showMenu
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 16
                            text: "more_vert"
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                Rectangle {
                    visible: card.showMenu
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 30
                    z: 10
                    width: 110
                    height: 68
                    radius: Appearance.rounding.small
                    color: Appearance.m3colors.m3surfaceContainer
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        MenuButton {
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Restore")
                            onClicked: {
                                card.showMenu = false;
                                if (root.section === "trash") Notes.restoreFromTrash(card.modelData.id);
                                else Notes.restoreFromArchive(card.modelData.id);
                            }
                        }
                        MenuButton {
                            Layout.fillWidth: true
                            buttonText: root.section === "trash" ? Translation.tr("Delete forever") : Translation.tr("Delete")
                            onClicked: {
                                card.showMenu = false;
                                if (root.section === "trash") Notes.permanentlyDelete(card.modelData.id);
                                else Notes.deleteNote(card.modelData.id, "archived");
                            }
                        }
                    }
                }
            }
        }
        }

        Loader {
            active: root.openNoteId.length > 0
            sourceComponent: NoteEditor {
                noteId: root.openNoteId
                location: root.section
                onBack: {
                    root.openNoteId = "";
                    if (root.section === "trash") Notes.refreshTrash();
                    else Notes.refreshArchived();
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.zoomImagePath.length > 0
        color: "#dd000000"
        z: 999
        MouseArea { anchors.fill: parent; onClicked: root.zoomImagePath = "" }
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: parent.height * 0.9
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: root.zoomImagePath.length > 0 ? `file://${root.zoomImagePath}?${root.zoomCacheBust}` : ""
        }
    }
}
