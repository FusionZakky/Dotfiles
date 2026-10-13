import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    required property string noteId
    required property string location // "active" | "archived" | "trash"
    property bool isNewNote: false
    property string initialTitle: ""
    property string initialType: "text" // "text" | "checklist"
    property int focusItemIndex: -1
    property bool isExpandedView: false
    signal back()
    signal expand()

    readonly property string sourceDir: location === "archived" ? Directories.notesArchiveDir
        : location === "trash" ? Directories.notesTrashDir
        : Directories.notesDir

    property string title: ""
    property var content: ""
    property var images: []
    property string noteType: "text" // "text" | "checklist" | "image" | "drawing"
    readonly property bool isPhotoNote: root.noteType === "image" || root.noteType === "drawing"


    readonly property bool isChecklist: Array.isArray(root.content)
    readonly property string assetDir: `${Directories.notesAssetsDir}/${root.noteId}`
    property bool titleEditing: false
    property var copyListEntries: []
    property string lastParsedCopylistText: ""
    property var parsedCopylistLines: []

    property string previewImagePath: ""
    property var noteColor: null
    property bool showColorPicker: false

    Component.onCompleted: {
        if (root.isNewNote) {
            const now = Date.now();
            const startingContent = root.initialType === "checklist" ? [] : "";
            root.parsedNoteObject = { id: root.noteId, title: root.initialTitle, type: root.initialType, content: startingContent, created: now, modified: now };
            root.title = root.initialTitle;
            root.content = startingContent;
            root.noteType = root.initialType;
            root.saveContent();
            if (root.initialType === "image") imageNoteCreateProc.running = true;
            else if (root.initialType === "drawing") root.launchDrawingWindow();
        } else {
            noteFile.reload();
        }
    }

    function updateChecklistItems(newItems) {
        root.content = newItems;
        root.saveContent();
    }

    function toggleChecklistItem(index) {
        const items = root.content.slice();
        items[index] = Object.assign({}, items[index], { checked: !items[index].checked });
        root.updateChecklistItems(items);
    }

    function setChecklistItemText(index, newText) {
        // Mutate in place and deliberately avoid reassigning root.content here:
        // reassigning it would reset the Repeater's model and destroy/recreate every
        // row's TextField mid-keystroke, kicking focus out after 1-2 characters.
        if (!root.content || !root.content[index]) return;
        root.content[index].text = newText;
        saveDebounce.restart();
    }

    function deleteChecklistItem(index) {
        const items = root.content.slice();
        items.splice(index, 1);
        root.updateChecklistItems(items);
    }

    function addChecklistItem(afterIndex) {
        const items = root.content ? root.content.slice() : [];
        const newItem = { id: `${Date.now()}-${Math.floor(Math.random() * 10000)}`, text: "", checked: false };
        let insertIndex;
        if (afterIndex === undefined || afterIndex === null || afterIndex < 0) {
            items.push(newItem);
            insertIndex = items.length - 1;
        } else {
            insertIndex = afterIndex + 1;
            items.splice(insertIndex, 0, newItem);
        }
        root.focusItemIndex = insertIndex;
        root.updateChecklistItems(items);
    }

    function launchDrawingWindow() {
        root.saveContent();
        const tmpPath = `/tmp/quickshell/notes-drawing-${root.noteId}-${Date.now()}.png`;
        drawingProc.pendingTmpPath = tmpPath;
        const path = FileUtils.trimFileProtocol(Quickshell.shellPath("NoteDrawingWindow.qml"));
        drawingProc.command = ["bash", "-c", `NOTES_DRAW_TMP_PATH='${tmpPath}' qs -p '${path}'`];
        drawingProc.running = true;
    }

    function saveContent() {
        // Collapse 3+ consecutive line breaks down to exactly 2 (enough to visually
        // separate text from the images row below), applied only at save time so
        // active typing/cursor position is never disturbed mid-edit.
        const cleanedContent = typeof root.content === "string"
            ? root.content.replace(/\n{3,}/g, "\n\n")
            : root.content;
        const payload = {
            title: root.title,
            type: root.noteType,
            color: root.noteColor,
            content: cleanedContent,
            modified: Date.now()
        }
        // Preserve "created" by merging rather than clobbering: read-modify-write via jq would be
        // ideal, but since we already hold the parsed object client-side we just re-stringify it here.
        noteFile.setText(JSON.stringify(Object.assign({}, root.parsedNoteObject, payload)));
        Notes.refreshActive();
    }

    property var parsedNoteObject: ({})

    function updateCopyListEntries() {
        const textValue = root.content;
        if (!textValue || textValue.length === 0) {
            lastParsedCopylistText = "";
            parsedCopylistLines = [];
            root.copyListEntries = [];
            return;
        }
        if (textValue !== lastParsedCopylistText) {
            const lineRegex = /(.*?)(\r?\n|$)/g;
            let match = null;
            const parsed = [];
            while ((match = lineRegex.exec(textValue)) !== null) {
                const lineText = match[1];
                const newlineText = match[2];
                const lineStart = match.index;
                const lineEnd = lineStart + lineText.length;
                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/);
                if (bulletMatch) {
                    parsed.push({ content: bulletMatch[1].trim(), start: lineStart, end: lineEnd });
                }
                if (newlineText === "") break;
            }
            lastParsedCopylistText = textValue;
            parsedCopylistLines = parsed;
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "arrow_back"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: {
                    root.saveContent();
                    root.back();
                }
            }

            MaterialTextField {
                id: titleField
                visible: !root.isPhotoNote
                Layout.fillWidth: true
                text: root.title
                enabled: root.location === "active"
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                onEditingFinished: {
                    root.title = text;
                    Notes.renameNote(root.noteId, text, root.location);
                }
            }

            Item { visible: root.isPhotoNote; Layout.fillWidth: true }

            RippleButton {
                visible: root.location === "active" && root.noteType === "text"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "photo_library"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: imageBrowseProc.running = true
                StyledToolTip {
                    text: Translation.tr("Browse for an image")
                }
            }

            RippleButton {
                visible: root.location === "active" && root.noteType === "text"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "draw"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: root.launchDrawingWindow()
                StyledToolTip {
                    text: Translation.tr("Draw")
                }
            }

            RippleButton {
                visible: root.location === "active"
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "palette"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: root.showColorPicker = !root.showColorPicker
                StyledToolTip {
                    text: Translation.tr("Note color")
                }
            }

            RippleButton {
                visible: !root.isExpandedView
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "open_in_full"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: {
                    root.saveContent();
                    root.expand();
                }
            }
        }

        Rectangle {
            visible: root.noteColor !== null && root.noteColor !== undefined
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: root.noteColor ?? "transparent"
        }

        Flow {
            visible: root.showColorPicker
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: Notes.colorPalette
                delegate: RippleButton {
                    required property string modelData
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: modelData
                    toggled: root.noteColor === modelData
                    onClicked: {
                        root.noteColor = modelData;
                        Notes.setNoteColor(root.noteId, modelData, root.location);
                        root.showColorPicker = false;
                    }
                }
            }
        }

        Connections {
            target: Notes
            function onImageOperationFinished(noteId) {
                if (noteId === root.noteId) noteFile.reload();
            }
        }

        ScrollView {
            id: contentScrollView
            visible: !root.isPhotoNote
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            WheelHandler {
                target: null
                onWheel: (event) => {
                    const flick = contentScrollView.contentItem;
                    const maxY = Math.max(0, flick.contentHeight - contentScrollView.height);
                    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - event.angleDelta.y / 120 * 40));
                }
            }

            ColumnLayout {
                width: contentScrollView.availableWidth
                spacing: 8

                StyledTextArea {
                    id: textInput
                    Layout.fillWidth: true
                    visible: !root.isChecklist && !root.isPhotoNote
                    wrapMode: TextEdit.Wrap
                    text: root.isChecklist ? "" : root.content
                    enabled: root.location === "active" && !root.isChecklist
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText
                    background: null
                    padding: 0
                    placeholderText: Translation.tr("Write something here...")

                    onTextChanged: {
                        if (root.isChecklist) return;
                        root.content = text;
                        if (activeFocus) saveDebounce.restart();
                        root.updateCopyListEntries();
                    }
                }

                ColumnLayout {
                    visible: root.isChecklist && !root.isPhotoNote
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root.isChecklist ? root.content : []
                        delegate: RowLayout {
                            id: checklistRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 8

                            RippleButton {
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.small
                                enabled: root.location === "active"
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: 24
                                    text: checklistRow.modelData.checked ? "check_box" : "check_box_outline_blank"
                                    color: checklistRow.modelData.checked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                }
                                onClicked: root.toggleChecklistItem(checklistRow.index)
                            }

                            StyledTextArea {
                                id: itemTextInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 6
                                wrapMode: TextEdit.Wrap
                                enabled: root.location === "active"
                                text: checklistRow.modelData.text
                                font.strikeout: checklistRow.modelData.checked
                                color: checklistRow.modelData.checked ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                background: null
                                padding: 0
                                onTextChanged: root.setChecklistItemText(checklistRow.index, text)
                                Keys.onPressed: (event) => {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                        root.addChecklistItem(checklistRow.index);
                                        event.accepted = true;
                                    }
                                }
                                Component.onCompleted: {
                                    if (checklistRow.index === root.focusItemIndex) {
                                        itemTextInput.forceActiveFocus();
                                        root.focusItemIndex = -1;
                                    }
                                }
                            }

                            RippleButton {
                                visible: root.location === "active"
                                Layout.alignment: Qt.AlignTop
                                implicitWidth: 28
                                implicitHeight: 28
                                buttonRadius: Appearance.rounding.small
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: 16
                                    text: "close"
                                    color: Appearance.colors.colOnLayer1
                                }
                                onClicked: root.deleteChecklistItem(checklistRow.index)
                            }
                        }
                    }

                    RippleButton {
                        visible: root.location === "active"
                        Layout.fillWidth: true
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        contentItem: RowLayout {
                            spacing: 4
                            MaterialSymbol { iconSize: 18; text: "add"; color: Appearance.colors.colOnLayer1 }
                            StyledText { text: Translation.tr("Add item"); color: Appearance.colors.colOnLayer1 }
                        }
                        onClicked: root.addChecklistItem()
                    }
                }

                Flow {
                    visible: root.images.length > 0 && !root.isPhotoNote
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8

                    Repeater {
                        // (photo-note single-image view is a separate Image below, outside this Repeater)
                        model: root.images
                        delegate: Item {
                            id: imageCard
                            required property var modelData
                            readonly property real aspect: thumbImage.implicitHeight > 0 ? thumbImage.implicitWidth / thumbImage.implicitHeight : 1
                            height: 180
                            width: height * aspect

                            Image {
                                id: thumbImage
                                anchors.fill: parent
                                source: `file://${root.assetDir}/${imageCard.modelData.filename}?${imageCard.modelData.addedAt}`
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.previewImagePath = `${root.assetDir}/${imageCard.modelData.filename}`
                            }

                            RippleButton {
                                visible: root.location === "active"
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                                onClicked: Notes.removeImage(root.noteId, imageCard.modelData.id, root.location)
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: 18
                                    color: Appearance.m3colors.m3onSurface
                                    text: "close"
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.isPhotoNote && root.images.length > 0

            Image {
                id: photoNoteImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: root.images.length > 0 ? `file://${root.assetDir}/${root.images[0].filename}?${root.images[0].addedAt}` : ""

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.previewImagePath = `${root.assetDir}/${root.images[0].filename}`
                }
            }

            RippleButton {
                visible: root.noteType === "drawing" && root.location === "active"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: 8
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                onClicked: root.editExistingDrawing()
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 18
                    color: Appearance.m3colors.m3onSurface
                    text: "edit"
                }
                StyledToolTip { text: Translation.tr("Edit drawing") }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.margins: 8
            horizontalAlignment: Text.AlignRight
            text: root.location !== "active" ? Translation.tr("Read-only")
                : (saveDebounce.running ? Translation.tr("Saving...") : Translation.tr("Saved"))
            color: Appearance.colors.colSubtext
        }
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: root.saveContent()
    }

    Process {
        id: imageNoteCreateProc
        command: ["kdialog", "--getopenfilename", FileUtils.trimFileProtocol(Directories.pictures)]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) Notes.addImageFromLocalFile(root.noteId, path, root.location);
            }
        }
        onExited: GlobalStates.sidebarLeftOpen = true;
    }

    Process {
        id: imageBrowseProc
        command: ["kdialog", "--getopenfilename", "--multiple", "--separate-output", FileUtils.trimFileProtocol(Directories.pictures)]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.trim().split("\n").filter(l => l.length > 0);
                if (paths.length > 0) Notes.addImagesFromLocalFiles(root.noteId, paths, root.location);
            }
        }
        onExited: {
            // The file-picker stealing focus dismisses the sidebar; force it back
            // open rather than digging into the exact dismiss-on-focus-loss trigger.
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    Process {
        id: drawingProc
        property string pendingTmpPath: ""
        onExited: {
            GlobalStates.sidebarLeftOpen = true;
            if (drawingProc.pendingTmpPath.length > 0) {
                Notes.addImageFromLocalFile(root.noteId, drawingProc.pendingTmpPath, root.location);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.previewImagePath.length > 0
        color: "#dd000000"
        z: 999
        MouseArea { anchors.fill: parent; onClicked: root.previewImagePath = "" }
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: parent.height * 0.9
            fillMode: Image.PreserveAspectFit
            source: root.previewImagePath.length > 0 ? `file://${root.previewImagePath}?${Date.now()}` : ""
            asynchronous: true
        }
    }

    FileView {
        id: noteFile
        path: `${root.sourceDir}/${root.noteId}.json`
        onLoaded: {
            try {
                const parsed = JSON.parse(noteFile.text());
                root.parsedNoteObject = parsed;
                root.title = parsed.title ?? Translation.tr("Untitled");
                root.content = (parsed.content !== undefined && parsed.content !== null) ? parsed.content : "";
                root.images = parsed.images ?? [];
                root.noteType = parsed.type ?? (Array.isArray(root.content) ? "checklist" : "text");
                root.noteColor = parsed.color ?? null;
            } catch (e) {
                console.log("[NoteEditor] Failed to parse note:", e);
            }
        }
        onLoadFailed: error => console.log("[NoteEditor] Load failed:", error)
    }
}
