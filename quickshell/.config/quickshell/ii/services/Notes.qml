pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Multi-note manager for the sidebar Notes tab.
 * Each note is its own JSON file: {id, title, content, created, modified}
 * Notes live in three states: active (Directories.notesDir), archived (Directories.notesArchiveDir),
 * and trash (Directories.notesTrashDir, auto-purged after 30 days by Directories.qml on shell startup).
 */
Singleton {
    id: root

    property var activeNotes: []
    property var archivedNotes: []
    property var trashNotes: []

    // Fixed, theme-independent palette (same idea as Google Keep's note colors) -
    // chosen purely for visual distinctness between notes, deliberately NOT tied
    // to Appearance's wallpaper-derived Material colors so they stay constant
    // even if the system theme changes.
    readonly property var colorPalette: [
        "#F28B82", "#FBBC04", "#FFF475", "#CCFF90", "#A7FFEB",
        "#CBF0F8", "#AECBFA", "#D7AEFB", "#FDCFE8", "#E6C9A8", "#E8EAED"
    ]

    function randomPaletteColor() {
        return root.colorPalette[Math.floor(Math.random() * root.colorPalette.length)];
    }

    function setNoteColor(id, color, location) {
        const dir = location === "archived" ? Directories.notesArchiveDir
            : location === "trash" ? Directories.notesTrashDir
            : Directories.notesDir;
        const path = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, dir));
        const escapedColor = CF.StringUtils.shellSingleQuoteEscape(color);
        const script = `
tmp=$(mktemp)
jq --arg c ${escapedColor} '.color = $c | .modified = (now * 1000 | floor)' ${path} > "$tmp" && mv "$tmp" ${path}
`.trim();
        setColorProc.exec(["bash", "-c", script]);
    }

    Process {
        id: setColorProc
        onExited: root.refreshAll()
    }

    function refreshActive() { listActiveProc.running = true }
    function refreshArchived() { listArchivedProc.running = true }
    function refreshTrash() { listTrashProc.running = true }
    function refreshAll() {
        refreshActive();
        refreshArchived();
        refreshTrash();
    }

    Component.onCompleted: refreshAll()

    function listScript(dir) {
        return `
for f in '${dir}'/*.json; do
    [ -e "$f" ] || continue
    id=$(basename "$f" .json)
    jq -c --arg id "$id" '{
        id: $id,
        title: (.title // "Untitled"),
        preview: (if (.content|type) == "array"
            then ((.content // []) | map((if .checked then "\u2611 " else "\u2610 " end) + (.text // "")) | join(" \u2022 ") | .[0:120])
            else ((.content // "") | gsub("\n"; " ") | .[0:120])
            end),
        modified: (.modified // 0),
        deletedAt: (.deletedAt // null),
        imageCount: ((.images // []) | length),
        images: (.images // []),
        type: (.type // "text"),
        color: (.color // null)
    }' "$f" 2>/dev/null
done | jq -s 'sort_by(-.modified)'
`.trim()
    }

    Process {
        id: listActiveProc
        command: ["bash", "-c", root.listScript(Directories.notesDir)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.activeNotes = text.trim().length > 0 ? JSON.parse(text) : [];
                } catch (e) {
                    console.log("[Notes] Failed to parse active notes list:", e);
                    root.activeNotes = [];
                }
            }
        }
    }

    Process {
        id: listArchivedProc
        command: ["bash", "-c", root.listScript(Directories.notesArchiveDir)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.archivedNotes = text.trim().length > 0 ? JSON.parse(text) : [];
                } catch (e) {
                    console.log("[Notes] Failed to parse archived notes list:", e);
                    root.archivedNotes = [];
                }
            }
        }
    }

    Process {
        id: listTrashProc
        command: ["bash", "-c", root.listScript(Directories.notesTrashDir)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.trashNotes = text.trim().length > 0 ? JSON.parse(text) : [];
                } catch (e) {
                    console.log("[Notes] Failed to parse trash notes list:", e);
                    root.trashNotes = [];
                }
            }
        }
    }

    function generateId() {
        return `${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    }

    function notePath(id, dir) {
        return `${dir}/${id}.json`;
    }

    FileView {
        id: createFile
        property string targetPath: ""
        path: targetPath
        blockLoading: true
    }

    /**
     * Creates a new note with the given title and empty content in the active directory.
     * Returns the new note's id.
     */
    function createNote(title, noteType) {
        const id = root.generateId();
        const now = Date.now();
        const data = {
            id: id,
            title: title && title.trim().length > 0 ? title.trim() : Translation.tr("Untitled"),
            type: noteType || "text",
            color: root.randomPaletteColor(),
            content: noteType === "checklist" ? [] : "",
            created: now,
            modified: now
        };
        createFile.targetPath = root.notePath(id, Directories.notesDir);
        createFile.setText(JSON.stringify(data));
        root.refreshActive();
        return id;
    }

    /**
     * Renames a note in place. location must be "active", "archived", or "trash".
     */
    function renameNote(id, newTitle, location) {
        const dir = location === "archived" ? Directories.notesArchiveDir
            : location === "trash" ? Directories.notesTrashDir
            : Directories.notesDir;
        const path = root.notePath(id, dir);
        const escapedPath = CF.StringUtils.shellSingleQuoteEscape(path);
        const escapedTitle = CF.StringUtils.shellSingleQuoteEscape(newTitle.trim());
        const script = `
tmp=$(mktemp)
jq --arg t ${escapedTitle} '.title = $t | .modified = (now * 1000 | floor)' ${escapedPath} > "$tmp" && mv "$tmp" ${escapedPath}
`.trim();
        renameProc.exec(["bash", "-c", script]);
    }

    Process {
        id: renameProc
        onExited: root.refreshAll()
    }

    function moveNote(id, fromDir, toDir) {
        const fromPath = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, fromDir));
        const toPath = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, toDir));
        moveProc.exec(["bash", "-c", `mv ${fromPath} ${toPath}`]);
    }

    Process {
        id: moveProc
        onExited: root.refreshAll()
    }

    function archiveNote(id) {
        root.moveNote(id, Directories.notesDir, Directories.notesArchiveDir);
    }

    function restoreFromArchive(id) {
        root.moveNote(id, Directories.notesArchiveDir, Directories.notesDir);
    }

    function deleteNote(id, fromLocation) {
        const fromDir = fromLocation === "archived" ? Directories.notesArchiveDir : Directories.notesDir;
        const fromPath = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, fromDir));
        const toPath = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, Directories.notesTrashDir));
        const script = `
tmp=$(mktemp)
jq '.deletedAt = (now*1000|floor)' ${fromPath} > "$tmp" && mv "$tmp" ${fromPath}
mv ${fromPath} ${toPath}
`.trim();
        stampAndTrashProc.exec(["bash", "-c", script]);
    }

    Process {
        id: stampAndTrashProc
        onExited: root.refreshAll()
    }

    function restoreFromTrash(id) {
        root.moveNote(id, Directories.notesTrashDir, Directories.notesDir);
    }

    function permanentlyDelete(id) {
        const path = CF.StringUtils.shellSingleQuoteEscape(root.notePath(id, Directories.notesTrashDir));
        const assetsPath = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${id}`);
        permanentDeleteProc.exec(["bash", "-c", `rm -f ${path}; rm -rf ${assetsPath}`]);
    }

    Process {
        id: permanentDeleteProc
        onExited: root.refreshTrash()
    }

    signal imageOperationFinished(string noteId)

    function generateImageId() {
        return `${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    }

    function notePathForLocation(id, location) {
        const dir = location === "archived" ? Directories.notesArchiveDir
            : location === "trash" ? Directories.notesTrashDir
            : Directories.notesDir;
        return root.notePath(id, dir);
    }

    /**
     * Attaches an already-decoded local image file to a note.
     * Detects the real file type (not filename-dependent), copies it into the
     * note's own asset subfolder, and appends a record to the note's "images" array.
     */
    function addImageFromLocalFile(noteId, sourceFilePath, location) {
        root.addImagesFromLocalFiles(noteId, [sourceFilePath], location);
    }

    /**
     * Same as addImageFromLocalFile, but for multiple files at once - batched into
     * a single shell script / single Process.exec() call. Calling exec() repeatedly
     * in a tight loop on the same Process is not queue-safe: a later call restarts
     * the process before the previous run's jq/cp has finished, silently dropping
     * every file but the last. Looping inside one bash invocation avoids that entirely.
     */
    function addImagesFromLocalFiles(noteId, sourceFilePaths, location) {
        addImageProc.pendingNoteId = noteId;
        const notePath = CF.StringUtils.shellSingleQuoteEscape(root.notePathForLocation(noteId, location));
        const assetDir = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${noteId}`);
        const fileListLines = sourceFilePaths.map(p => CF.StringUtils.shellSingleQuoteEscape(p)).join("\n")
        const script = `
mkdir -p ${assetDir}
tmp="${notePath}"
while IFS= read -r src; do
    [ -z "$src" ] && continue
    imageId="$(date +%s%3N)-$RANDOM"
    ext=$(file -b --extension "$src" | cut -d/ -f1)
    [ "$ext" = "???" ] && ext="png"
    target="${assetDir}/$imageId.$ext"
    cp "$src" "$target" || continue
    tmpfile=$(mktemp)
    jq --arg id "$imageId" --arg filename "$imageId.$ext" --argjson now "$(date +%s%3N)" \
        '.images = ((.images // []) + [{id: $id, filename: $filename, addedAt: $now}])' \
        "$tmp" > "$tmpfile" && mv "$tmpfile" "$tmp"
done <<'FILELIST'
${fileListLines}
FILELIST
`.trim();
        addImageProc.exec(["bash", "-c", script]);
    }

    /**
     * Attaches the current clipboard image (via cliphist) to a note.
     * Mirrors the decode pattern already used for AI chat image attachments.
     */
    function addImageFromClipboardEntry(noteId, cliphistEntry, location) {
        addImageProc.pendingNoteId = noteId;
        const notePath = CF.StringUtils.shellSingleQuoteEscape(root.notePathForLocation(noteId, location));
        const assetDir = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${noteId}`);
        const imageId = root.generateImageId();
        const escapedEntry = CF.StringUtils.shellSingleQuoteEscape(cliphistEntry);
        const script = `
mkdir -p ${assetDir}
tmpfile=$(mktemp)
echo '${escapedEntry}' | cliphist decode > "$tmpfile"
ext=$(file -b --extension "$tmpfile" | cut -d/ -f1)
[ "$ext" = "???" ] && ext="png"
target="${assetDir}/${imageId}.$ext"
mv "$tmpfile" "$target"
tmp=$(mktemp)
jq --arg id "${imageId}" --arg filename "${imageId}.$ext" --argjson now "$(date +%s%3N)" \
    '.images = ((.images // []) + [{id: $id, filename: $filename, addedAt: $now}])' \
    ${notePath} > "$tmp" && mv "$tmp" ${notePath}
`.trim();
        addImageProc.exec(["bash", "-c", script]);
    }

    Process {
        id: addImageProc
        property string pendingNoteId: ""
        onExited: {
            root.refreshAll();
            root.imageOperationFinished(addImageProc.pendingNoteId);
        }
    }

    /**
     * Writes a base64-encoded PNG (e.g. from Canvas.toDataURL()) directly into a
     * note's asset folder - no source file needed. Used by the in-process drawing
     * overlay, which lives in the same process/singleton as this service, so no
     * cross-process handoff is required at all.
     */
    function addImageFromDataUrl(noteId, base64Data, location) {
        addImageProc.pendingNoteId = noteId;
        const notePath = CF.StringUtils.shellSingleQuoteEscape(root.notePathForLocation(noteId, location));
        const assetDir = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${noteId}`);
        const imageId = root.generateImageId();
        const script = `
mkdir -p ${assetDir}
target="${assetDir}/${imageId}.png"
echo '${base64Data}' | base64 -d > "$target"
tmp=$(mktemp)
jq --arg id "${imageId}" --arg filename "${imageId}.png" --argjson now "$(date +%s%3N)" \
    '.images = ((.images // []) + [{id: $id, filename: $filename, addedAt: $now}])' \
    ${notePath} > "$tmp" && mv "$tmp" ${notePath}
`.trim();
        addImageProc.exec(["bash", "-c", script]);
    }

    /**
     * Overwrites an existing image's file content in place (same imageId, same
     * filename) - used when re-editing a drawing rather than attaching a new one.
     */
    /**
     * Single canonical entry point for opening the drawing canvas to edit an
     * existing image (as opposed to creating a brand new drawing). Handles
     * launching the window, waiting for it to close, and calling
     * replaceImageFromLocalFile - the ONE place this logic should live, since
     * three separate near-duplicate copies of this launch code caused real,
     * hard-to-track bugs.
     */
    function editDrawing(noteId, imagePath, imageId, location) {
        const tmpPath = `/tmp/quickshell/notes-drawing-${noteId}-${Date.now()}.png`;
        editDrawingProc.pendingNoteId = noteId;
        editDrawingProc.pendingTmpPath = tmpPath;
        editDrawingProc.pendingImageId = imageId;
        editDrawingProc.pendingLocation = location;
        const shellPath = CF.FileUtils.trimFileProtocol(Quickshell.shellPath("NoteDrawingWindow.qml"));
        const escapedBg = CF.StringUtils.shellSingleQuoteEscape(imagePath);
        const escapedTmp = CF.StringUtils.shellSingleQuoteEscape(tmpPath);
        const escapedShellPath = CF.StringUtils.shellSingleQuoteEscape(shellPath);
        editDrawingProc.command = ["bash", "-c", `NOTES_DRAW_BG_PATH=${escapedBg} NOTES_DRAW_TMP_PATH=${escapedTmp} qs -p ${escapedShellPath}`];
        editDrawingProc.running = true;
    }

    Process {
        id: editDrawingProc
        property string pendingNoteId: ""
        property string pendingTmpPath: ""
        property string pendingImageId: ""
        property string pendingLocation: "active"
        onExited: {
            GlobalStates.sidebarLeftOpen = true;
            if (editDrawingProc.pendingTmpPath.length > 0) {
                Notes.replaceImageFromLocalFile(editDrawingProc.pendingNoteId, editDrawingProc.pendingImageId, editDrawingProc.pendingTmpPath, editDrawingProc.pendingLocation);
            }
        }
    }

    function replaceImageFromLocalFile(noteId, imageId, sourceFilePath, location) {
        addImageProc.pendingNoteId = noteId;
        const notePath = CF.StringUtils.shellSingleQuoteEscape(root.notePathForLocation(noteId, location));
        const assetDir = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${noteId}`);
        const escapedSource = CF.StringUtils.shellSingleQuoteEscape(sourceFilePath);
        const escapedImageId = CF.StringUtils.shellSingleQuoteEscape(imageId);
        const script = `
filename=$(jq -r --arg id ${escapedImageId} '.images[]? | select(.id == $id) | .filename' ${notePath})
if [ -n "$filename" ]; then
    cp ${escapedSource} "${assetDir}/$filename"
    tmp=$(mktemp)
    jq --arg id ${escapedImageId} --argjson now "$(date +%s%3N)" \
        '.images = ((.images // []) | map(if .id == $id then . + {addedAt: $now} else . end)) | .modified = $now' \
        ${notePath} > "$tmp" && mv "$tmp" ${notePath}
fi
`.trim();
        addImageProc.exec(["bash", "-c", script]);
    }

    function removeImage(noteId, imageId, location) {
        removeImageProc.pendingNoteId = noteId;
        const notePath = CF.StringUtils.shellSingleQuoteEscape(root.notePathForLocation(noteId, location));
        const assetDir = CF.StringUtils.shellSingleQuoteEscape(`${Directories.notesAssetsDir}/${noteId}`);
        const script = `
filename=$(jq -r --arg id "${imageId}" '.images[]? | select(.id == $id) | .filename' ${notePath})
[ -n "$filename" ] && rm -f "${assetDir}/$filename"
tmp=$(mktemp)
jq --arg id "${imageId}" '.images = ((.images // []) | map(select(.id != $id)))' ${notePath} > "$tmp" && mv "$tmp" ${notePath}
`.trim();
        removeImageProc.exec(["bash", "-c", script]);
    }

    Process {
        id: removeImageProc
        property string pendingNoteId: ""
        onExited: {
            root.refreshAll();
            root.imageOperationFinished(removeImageProc.pendingNoteId);
        }
    }
}
