import QtQuick
import qs.services

NotesGridSection {
    section: "archived"
    Component.onCompleted: Notes.refreshArchived()
}
