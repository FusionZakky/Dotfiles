import QtQuick
import qs.services

NotesGridSection {
    section: "trash"
    Component.onCompleted: Notes.refreshTrash()
}
