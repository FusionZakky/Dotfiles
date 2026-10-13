//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.notes

ApplicationWindow {
    id: root
    property string noteId: Quickshell.env("NOTES_EXPAND_ID") || ""

    visible: true
    title: Translation.tr("Note")
    minimumWidth: 700
    minimumHeight: 600
    maximumWidth: 700
    maximumHeight: 600
    width: 700
    height: 600
    color: Appearance.m3colors.m3background

    Component.onCompleted: {
        Config.readWriteDelay = 0;
        MaterialThemeLoader.reapplyTheme();
    }

    onClosing: Qt.quit()

    NoteEditor {
        anchors.fill: parent
        anchors.margins: 8
        noteId: root.noteId
        location: "active"
        isExpandedView: true
        onBack: root.close()
    }
}
