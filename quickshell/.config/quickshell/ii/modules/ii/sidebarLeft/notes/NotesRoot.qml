import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var tabButtonList: [
        { "icon": "sticky_note_2", "name": Translation.tr("Active") },
        { "icon": "archive", "name": Translation.tr("Archive") },
        { "icon": "delete", "name": Translation.tr("Trash") }
    ]

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) tabBar.incrementCurrentIndex();
            else if (event.key === Qt.Key_PageUp) tabBar.decrementCurrentIndex();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            currentIndex: tabBar.currentIndex

            NotesActiveView {}
            NotesArchiveTab {}
            NotesTrashTab {}
        }
    }
}
