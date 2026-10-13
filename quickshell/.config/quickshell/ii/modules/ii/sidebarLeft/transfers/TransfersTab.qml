import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

Item {
id: root
property string zoomImagePath: ""
property string zoomTextPath: ""
property string zoomTextContent: ""
property bool isRawText: false

Component.onCompleted: LocalSendHistory.refresh()

FileView {
    id: textReaderFile
    path: root.zoomTextPath
    onLoaded: if (!root.isRawText) root.zoomTextContent = textReaderFile.text()
    onLoadFailed: if (!root.isRawText && root.zoomTextPath.length > 0) root.zoomTextContent = "Failed to load text file."
}

Timer {
    interval: 1000
    running: root.visible
    repeat: true
    onTriggered: LocalSendHistory.refresh()
}

GridView {
    id: grid
    anchors.fill: parent
    anchors.margins: 8
    clip: true
    visible: LocalSendHistory.entries.length > 0
    readonly property int minCellWidth: 150
    readonly property int columns: Math.max(1, Math.floor(width / minCellWidth))
    cellWidth: width / columns
    cellHeight: 100
    model: LocalSendHistory.entries

    delegate: Item {
        id: card
        required property var modelData
        property bool showMenu: false
        z: showMenu ? 100 : 0
        width: grid.cellWidth
        height: grid.cellHeight
        readonly property bool isImage: card.modelData.fileType === "image"

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true
            
            Image {
                visible: card.isImage
                anchors.fill: parent
                source: card.isImage && card.modelData.path ? `file://${card.modelData.path}` : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            ColumnLayout {
                visible: !card.isImage
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 32
                    text: card.modelData.fileType === "text" ? "short_text" : "description"
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                    text: card.modelData.fileName
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 4
                radius: 3
                color: "#aa000000"
                visible: card.isImage
                implicitHeight: senderLabel.implicitHeight + 4
                StyledText {
                    id: senderLabel
                    anchors.centerIn: parent
                    font.pixelSize: 9
                    color: "white"
                    elide: Text.ElideRight
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    text: `${card.modelData.senderAlias} \u2022 ${LocalSendHistory.formatSize(card.modelData.fileSize)}`
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (card.showMenu) { card.showMenu = false; return; }
                    
                    if (card.isImage && card.modelData.path) {
                        root.zoomImagePath = card.modelData.path;
                    } else if (card.modelData.fileType === "text" || card.modelData.fileType === "message") {
                        root.isRawText = true;
                        root.zoomTextPath = ""; 
                        root.zoomTextContent = card.modelData.fileName;
                    } else if (card.modelData.path && (card.modelData.fileName.endsWith(".txt") || card.modelData.fileName.endsWith(".md") || card.modelData.fileName.endsWith(".json") || card.modelData.fileName.endsWith(".csv"))) {
                        root.isRawText = false;
                        root.zoomTextContent = "Loading...";
                        root.zoomTextPath = card.modelData.path;
                    } else if (card.modelData.path) {
                        LocalSendHistory.openFile(card.modelData.path);
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
                        buttonText: "Copy"
                        onClicked: {
                            card.showMenu = false;
                            if (card.modelData.fileType === "text" || card.modelData.fileType === "message") {
                                Quickshell.execDetached(["wl-copy", card.modelData.fileName]);
                            } else if (card.modelData.path) {
                                if (card.modelData.fileType === "image") {
                                    // Transforms the image to PNG directly into the clipboard so browsers don't panic
                                    const imgCmd = `if command -v magick &> /dev/null; then magick "${card.modelData.path}" png:- | wl-copy -t image/png; elif command -v convert &> /dev/null; then convert "${card.modelData.path}" png:- | wl-copy -t image/png; else wl-copy -t $(file -b --mime-type "${card.modelData.path}") < "${card.modelData.path}"; fi`;
                                    Quickshell.execDetached(["bash", "-c", imgCmd]);
                                } else {
                                    Quickshell.execDetached(["wl-copy", card.modelData.path]);
                                }
                            }
                        }
                    }
                    MenuButton {
                        Layout.fillWidth: true
                        buttonText: "Delete"
                        onClicked: {
                            card.showMenu = false;
                            if (card.modelData.path) Quickshell.execDetached(["rm", "-f", card.modelData.path]);
                            LocalSendHistory.deleteEntry(card.modelData.id);
                        }
                    }
                }
            }
        }
    }
}

// --- POPUPS ---

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
        source: root.zoomImagePath.length > 0 ? `file://${root.zoomImagePath}` : ""
    }
}

Rectangle {
    anchors.fill: parent
    visible: root.zoomTextContent.length > 0
    color: Appearance.m3colors.m3surface
    z: 999
    MouseArea { anchors.fill: parent } 
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
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
                onClicked: { root.zoomTextPath = ""; root.zoomTextContent = ""; root.isRawText = false; }
            }
            
            Item { Layout.fillWidth: true }
            
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 20
                    text: "content_copy"
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: { 
                    Quickshell.execDetached(["wl-copy", root.zoomTextContent]);
                }
            }
        }
        
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            
            StyledTextArea {
                id: textArea
                text: root.zoomTextContent
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.normal
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
                background: null
                padding: 0
            }
        }
    }
}

FloatingActionButton {
    id: powerBtn
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.margins: 16
    anchors.rightMargin: 24
    z: 100 
    iconText: "power_settings_new"
    opacity: isActive ? 1.0 : 0.4
    
    property bool isActive: true

    Process { 
        id: toggleService
        command: ["bash", "-c", "systemctl --user is-active --quiet localsendd && systemctl --user stop localsendd || systemctl --user start localsendd"]
        onExited: checkState.running = true
    }

    Process {
        id: checkState
        command: ["systemctl", "--user", "is-active", "--quiet", "localsendd"]
        onExited: powerBtn.isActive = (exitCode === 0)
    }

    Component.onCompleted: checkState.running = true

    onClicked: {
        powerBtn.isActive = !powerBtn.isActive
        toggleService.running = true
    }
}
}
