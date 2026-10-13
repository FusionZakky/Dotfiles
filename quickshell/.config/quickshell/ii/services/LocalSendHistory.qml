pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
id: root
property string historyPath: Quickshell.shellPath("~/.local/share/org.localsend.localsend_app/shared_preferences.json")
property var entries: []
property bool loadFailed: false

function refresh() { historyFile.reload() }

Component.onCompleted: refresh()

FileView {
    id: historyFile
    path: root.historyPath
    onLoaded: {
        try {
            const raw = JSON.parse(historyFile.text());
            const rawHistory = raw["flutter.ls_receive_history"] ?? [];
            const parsed = rawHistory.map(s => {
                try { return JSON.parse(s); } catch (e) { return null; }
            }).filter(e => e !== null);
            parsed.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
            root.entries = parsed;
            root.loadFailed = false;
        } catch (e) {
            root.entries = [];
            root.loadFailed = true;
        }
    }
    onLoadFailed: error => {
        root.entries = [];
        root.loadFailed = true;
    }
}

function deleteEntry(id) {
    Quickshell.execDetached(["bash", "-c", `python3 -c "
import json, os
p = os.path.expanduser('~/.local/share/org.localsend.localsend_app/shared_preferences.json')
if os.path.exists(p):
d = json.load(open(p, 'r', encoding='utf-8'))
h = [json.loads(x) for x in d.get('flutter.ls_receive_history', [])]
target = next((x for x in h if str(x.get('id')) == '${id}'), None)
if target and 'file_name' in target:
    # Try cleaning up the actual file from disk if path exists
    pass
h = [x for x in h if str(x.get('id')) != '${id}']
d['flutter.ls_receive_history'] = [json.dumps(x, separators=(',', ':'), ensure_ascii=False) for x in h]
json.dump(d, open(p, 'w', encoding='utf-8'), separators=(',', ':'), ensure_ascii=False)
" && sleep 0.2`]);
    refresh();
}

function copyContent(path, fileType) {
    if (fileType === "image") {
        Quickshell.execDetached(["bash", "-c", `wl-copy --type image/png < "${path}"`]);
    } else {
        Quickshell.execDetached(["bash", "-c", `cat "${path}" | wl-copy`]);
    }
}

function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

function openFile(path) { Quickshell.execDetached(["xdg-open", path]); }
function openContainingFolder(path) { Quickshell.execDetached(["xdg-open", path.substring(0, path.lastIndexOf("/"))]); }
}
