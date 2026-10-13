import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.notes

Item {
    id: root
    property string openNoteId: ""
    property bool openNoteIsNew: false
    property string openNoteInitialTitle: ""
    property string openNoteInitialType: "text"
    property bool showCreateDialog: false
    property string expandedNoteId: ""
    property string zoomNoteId: ""
    property string zoomImagePath: ""
    property string zoomNoteType: ""
    property string zoomCacheBust: ""

    function createAndOpen(noteType, title) {
        const id = Notes.createNote(title, noteType);
        createDialogLoader.item.show = false;
        root.showCreateDialog = false;
        root.openNoteInitialTitle = title;
        root.openNoteInitialType = noteType;
        root.openNoteIsNew = true;
        root.openNoteId = id;
    }

    function launchExpandedNote(noteId) {
        const path = FileUtils.trimFileProtocol(Quickshell.shellPath("ExpandedNoteWindow.qml"));
        Quickshell.execDetached(["bash", "-c", `NOTES_EXPAND_ID='${noteId}' qs -p '${path}'`]);
    }



    Component.onCompleted: Notes.refreshActive()

    StackLayout {
        anchors.fill: parent
        currentIndex: root.openNoteId.length > 0 ? 1 : 0

        // Page 0: grid
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
                model: Notes.activeNotes
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
                                wrapMode: Text.Wrap
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
                        }

                        // Debug badge, moved bottom-right so the heading stays clearly visible
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 4
                            radius: 3
                            color: "#aa000000"
                            implicitWidth: debugTypeLabel.implicitWidth + 8
                            implicitHeight: debugTypeLabel.implicitHeight + 4
                            StyledText {
                                id: debugTypeLabel
                                anchors.centerIn: parent
                                font.pixelSize: 9
                                color: "white"
                                text: card.modelData.type ?? "text"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (card.isPhotoCard) {
                                    root.zoomNoteId = card.modelData.id;
                                    root.zoomNoteType = card.modelData.type;
                                    root.zoomImagePath = `${Directories.notesAssetsDir}/${card.modelData.id}/${card.modelData.images[0].filename}`;
                                    root.zoomCacheBust = String(card.modelData.images[0].addedAt);
                                } else {
                                    root.openNoteIsNew = false;
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
                        width: 100
                        height: 68
                        radius: Appearance.rounding.small
                        color: Appearance.m3colors.m3surfaceContainer
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            MenuButton {
                                Layout.fillWidth: true
                                buttonText: Translation.tr("Archive")
                                onClicked: {
                                    card.showMenu = false;
                                    Notes.archiveNote(card.modelData.id);
                                }
                            }
                            MenuButton {
                                Layout.fillWidth: true
                                buttonText: Translation.tr("Delete")
                                onClicked: {
                                    card.showMenu = false;
                                    Notes.deleteNote(card.modelData.id, "active");
                                }
                            }
                        }
                    }
                }
            }

            FloatingActionButton {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                anchors.rightMargin: 24
                iconText: "add"
                onClicked: root.showCreateDialog = true
            }
        }

        // Page 1: editor
        Loader {
            active: root.openNoteId.length > 0
            sourceComponent: NoteEditor {
                noteId: root.openNoteId
                location: "active"
                isNewNote: root.openNoteIsNew
                initialTitle: root.openNoteInitialTitle
                initialType: root.openNoteInitialType
                onBack: {
                    root.openNoteId = "";
                    root.openNoteIsNew = false;
                    Notes.refreshActive();
                }
                onExpand: {
                    root.launchExpandedNote(root.openNoteId);
                    root.openNoteId = "";
                    root.openNoteIsNew = false;
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.zoomImagePath.length > 0
        color: "#dd000000"
        z: 999

        MouseArea {
            anchors.fill: parent
            onClicked: { root.zoomImagePath = ""; root.zoomNoteId = ""; }
        }

        Image {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: parent.height * 0.9
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            source: root.zoomImagePath.length > 0 ? `file://${root.zoomImagePath}?${root.zoomCacheBust}` : ""
        }

        RowLayout {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 8

            RippleButton {
                visible: root.zoomNoteType === "drawing"
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                onClicked: {
                    const zid = root.zoomNoteId;
                    const zpath = root.zoomImagePath;
                    root.zoomImagePath = "";
                    root.zoomNoteId = "";
                    root.zoomNoteType = "";
                    const note = Notes.activeNotes.find(n => n.id === zid);
                    const imageId = note && note.images && note.images.length > 0 ? note.images[0].id : "";
                    Notes.editDrawing(zid, zpath, imageId, "active");
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    color: Appearance.m3colors.m3onSurface
                    text: "edit"
                }
                StyledToolTip { text: Translation.tr("Edit drawing") }
            }

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                onClicked: {
                    root.launchExpandedNote(root.zoomNoteId);
                    root.zoomImagePath = "";
                    root.zoomNoteId = "";
                    root.zoomNoteType = "";
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    color: Appearance.m3colors.m3onSurface
                    text: "open_in_full"
                }
                StyledToolTip { text: Translation.tr("Pop out") }
            }
        }
    }

    Loader {
        id: createDialogLoader
        anchors.fill: parent
        active: root.showCreateDialog
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        sourceComponent: WindowDialog {
            id: createDialog
            property string chosenType: ""
            onDismiss: {
                createDialog.show = false;
                root.showCreateDialog = false;
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("New note")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButton {
                    Layout.fillWidth: true
                    toggled: createDialog.chosenType === "text"
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    buttonRadius: Appearance.rounding.small
                    implicitHeight: 32
                    contentItem: StyledText { horizontalAlignment: Text.AlignHCenter; text: Translation.tr("Text") }
                    onClicked: { createDialog.chosenType = "text"; titleInput.forceActiveFocus(); }
                }
                RippleButton {
                    Layout.fillWidth: true
                    toggled: createDialog.chosenType === "checklist"
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    buttonRadius: Appearance.rounding.small
                    implicitHeight: 32
                    contentItem: StyledText { horizontalAlignment: Text.AlignHCenter; text: Translation.tr("Checklist") }
                    onClicked: { createDialog.chosenType = "checklist"; titleInput.forceActiveFocus(); }
                }
                RippleButton {
                    Layout.fillWidth: true
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    buttonRadius: Appearance.rounding.small
                    implicitHeight: 32
                    contentItem: StyledText { horizontalAlignment: Text.AlignHCenter; text: Translation.tr("Image") }
                    onClicked: root.createAndOpen("image", Translation.tr("Untitled"))
                }
                RippleButton {
                    Layout.fillWidth: true
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    buttonRadius: Appearance.rounding.small
                    implicitHeight: 32
                    contentItem: StyledText { horizontalAlignment: Text.AlignHCenter; text: Translation.tr("Drawing") }
                    onClicked: root.createAndOpen("drawing", Translation.tr("Untitled"))
                }
            }

            MaterialTextField {
                id: titleInput
                visible: createDialog.chosenType === "text" || createDialog.chosenType === "checklist"
                Layout.fillWidth: true
                placeholderText: Translation.tr("Note title")
                onAccepted: {
                    if (text.trim().length === 0) return;
                    const enteredTitle = text.trim();
                    const chosenType = createDialog.chosenType;
                    const id = Notes.createNote(enteredTitle, chosenType);
                    createDialog.show = false;
                    root.showCreateDialog = false;
                    // Set every supporting property BEFORE openNoteId: setting openNoteId
                    // immediately activates the Loader, which instantiates NoteEditor and
                    // runs its Component.onCompleted synchronously right then - any property
                    // set AFTER openNoteId is too late for that one-time initialization.
                    root.openNoteInitialTitle = enteredTitle;
                    root.openNoteInitialType = chosenType;
                    root.openNoteIsNew = true;
                    root.openNoteId = id;
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        createDialog.show = false;
                        root.showCreateDialog = false;
                    }
                }
            }
        }
    }
}
