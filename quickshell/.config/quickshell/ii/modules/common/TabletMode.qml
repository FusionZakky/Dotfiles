pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs

/**
 * Tablet mode state: the single source of truth for every piece of tablet-only UI.
 * ~/.local/bin/tablet-mode writes "1" or "0" into $XDG_RUNTIME_DIR/tablet-mode (a tmpfs file, so it can never
 * outlive a login session). Everything tablet-only is bound to `active` and is destroyed, not hidden,
 * when it goes false, so nothing can bleed into laptop mode.
 */
Singleton {
    id: root

    property bool active: false
    property int rotations: 0 // bumps every time the screen is rotated (drives the fade overlay)
    property bool gridOpen: false // the touch app launcher (AppGrid)

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    onActiveChanged: {
        if (!root.active) {
            // leaving tablet mode: close everything tablet mode may have opened
            GlobalStates.oskOpen = false;
            GlobalStates.overviewOpen = false;
            root.gridOpen = false;
        }
    }

    FileView {
        id: stateView
        path: `${root.runtimeDir}/tablet-mode`
        watchChanges: true
        printErrors: false // a missing file is normal until the first fold, not an error
        onFileChanged: this.reload()
        onLoaded: root.active = (text().trim() === "1")
        onLoadFailed: root.active = false
    }
    Timer { // only polls until the file exists, then the file watcher takes over
        interval: 1000
        repeat: true
        running: !stateView.loaded
        onTriggered: stateView.reload()
    }

    FileView {
        id: rotationView
        path: `${root.runtimeDir}/tablet-rotated`
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: if (root.active) root.rotations += 1
    }
    Timer {
        interval: 1000
        repeat: true
        running: !rotationView.loaded
        onTriggered: rotationView.reload()
    }
}
