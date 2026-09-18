import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.utils
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: content
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3background
    border.color: Appearance.colors.colLayer2
    border.width: 1

    property bool searching: false
    property string lastQuery: ""
    property bool browsingDefault: true
    property var allPackageNames: []
    property int enrichBatchIndex: 0
    property int enrichBatchSize: 150
    property string loadingStatus: ""
    property bool showOnlyInstalled: false

    // Source of truth for currently loaded items (browse list or search
    // results) - resultsListModel is always rebuilt FROM this, rather than
    // mutated in place, to avoid index-drift bugs across async updates.
    property var masterItems: []

    // Real installed-package set from `pacman -Qq`, NOT scraped from
    // `-Si` output (which doesn't reliably include an [installed] marker
    // the way `-Ss`/`-Sl` do - that was a real bug in the previous
    // default-browse-list installed detection).
    property var installedNames: ({})
    property var explicitNames: ({}) // pacman -Qqe - apps you asked for, not pulled-in dependencies
    property var foreignNames: ({}) // pacman -Qm - AUR/manually-built, not in any sync repo
    property var installedViewItems: [] // dedicated Installed-only dataset, independent of the repo-only browse list
    property var hiddenNames: ({}) // manually hidden from Installed view, persisted to disk
    property var baseGroupNames: ({}) // members of base/base-devel groups - excluded from Installed view as system setup, not user apps

    // Arm-and-confirm state, now covering three action types instead of
    // just install.
    property var armedAction: null // { type: "install"|"uninstall"|"update", key: string }

    ListModel {
        id: resultsListModel
        dynamicRoles: true
    }

    Timer {
        id: armDisarmTimer
        interval: 4000
        repeat: false
        onTriggered: content.armedAction = null
    }

    function armedActionKey() {
        return content.armedAction ? (content.armedAction.type + ":" + content.armedAction.key) : ""
    }

    // ------------------------------------------------------------
    // Installed-package set - loaded once per popup open (Loader
    // recreates this component each time GlobalStates.packageInstallerOpen
    // toggles true, so this naturally refreshes on every reopen)
    // ------------------------------------------------------------
    Process {
        id: installedListProc
        command: ["pacman", "-Qq"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").map(n => n.trim()).filter(n => n.length > 0)
                const set = {}
                names.forEach(n => set[n] = true)
                content.installedNames = set
                content.render()
            }
        }
    }

    Process {
        id: explicitListProc
        command: ["pacman", "-Qqe"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").map(n => n.trim()).filter(n => n.length > 0)
                const set = {}
                names.forEach(n => set[n] = true)
                content.explicitNames = set
                content.loadInstalledView()
                content.render()
            }
        }
    }

    Process {
        id: foreignListProc
        command: ["pacman", "-Qqm"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").map(n => n.trim()).filter(n => n.length > 0)
                const set = {}
                names.forEach(n => set[n] = true)
                content.foreignNames = set
                content.loadInstalledView()
                content.render()
            }
        }
    }

    Process {
        id: baseGroupProc
        command: ["pacman", "-Qg", "base", "base-devel"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Format: "<group> <pkgname>" per line
                const lines = text.split("\n").map(l => l.trim()).filter(l => l.length > 0)
                const set = {}
                lines.forEach(line => {
                    const parts = line.split(/\s+/)
                    if (parts.length >= 2) set[parts[1]] = true
                })
                content.baseGroupNames = set
                content.loadInstalledView()
                content.render()
            }
        }
    }

    // pacman -Qi works for ANY installed package regardless of origin
    // (repo or AUR/foreign), unlike -Si which only knows about sync repos -
    // this is what makes it possible to show real details for AUR-origin
    // installed packages like spotify/slack/vscode/burpsuite.
    Process {
        id: installedDetailProc
        command: ["pacman", "-Qi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const blocks = text.split(/\n\s*\n/)
                const items = []
                for (const block of blocks) {
                    const nameM = block.match(/^Name\s*:\s*(\S+)/m)
                    if (!nameM) continue
                    const name = nameM[1]
                    if (!content.explicitNames[name]) continue // only explicitly-installed apps, not pulled-in deps
                    if (content.baseGroupNames[name]) continue // exclude base/base-devel group members (rarely matches on current Arch, kept harmless)
                    const descM = block.match(/^Description\s*:\s*(.+)$/m)
                    const versM = block.match(/^Version\s*:\s*(.+)$/m)
                    const instM = block.match(/^Installed Size\s*:\s*(.+)$/m)
                    items.push({
                        source: content.foreignNames[name] ? "AUR" : "Repo",
                        name: name,
                        version: versM ? versM[1].trim() : "",
                        installed: true,
                        description: descM ? descM[1].trim() : "",
                        meta: instM ? "Inst: " + instM[1].trim() : ""
                    })
                }
                items.sort((a, b) => a.name.localeCompare(b.name))
                console.log("[PkgInstaller DEBUG] explicitNames count:", Object.keys(content.explicitNames).length)
                console.log("[PkgInstaller DEBUG] foreignNames count:", Object.keys(content.foreignNames).length)
                console.log("[PkgInstaller DEBUG] installedViewItems count:", items.length)
                content.installedViewItems = items
                content.render()
            }
        }
    }

    function loadInstalledView() {
        // Wait until both explicit and foreign name sets are loaded before
        // running the detail query, since it needs both to classify results.
        if (Object.keys(content.explicitNames).length === 0) return
        installedDetailProc.running = true
    }

    // ------------------------------------------------------------
    // DEFAULT BROWSE MODE
    // ------------------------------------------------------------
    Process {
        id: nameListProc
        command: ["pacman", "-Slq"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").map(n => n.trim()).filter(n => n.length > 0)
                names.sort((a, b) => a.localeCompare(b))
                content.allPackageNames = names
                content.masterItems = names.map(name => ({
                    source: "Repo", name: name, version: "", installed: !!content.installedNames[name],
                    description: "", meta: ""
                }))
                content.render()
                content.loadingStatus = `Loaded ${names.length} package names, fetching details...`
                content.enrichBatchIndex = 0
                content.enrichNextBatch()
            }
        }
    }

    Process {
        id: enrichProc
        stdout: StdioCollector {
            onStreamFinished: {
                const details = content.parseSiOutput(text)
                const changedIndices = []
                content.masterItems = content.masterItems.map((item, idx) => {
                    if (details[item.name]) {
                        item.description = details[item.name].description
                        item.meta = details[item.name].meta
                        item.installed = !!content.installedNames[item.name]
                        changedIndices.push(idx)
                    }
                    return item
                })
                // Update only the rows that actually changed, in place, so
                // scrolling is never disrupted - a full clear+rebuild (what
                // render() does) resets scroll position every time regardless
                // of any save/restore logic wrapped around it. This only
                // works because browse-mode indices stay 1:1 aligned between
                // masterItems and resultsListModel (true as long as we're not
                // mid-search and not viewing Installed-only).
                if (!content.showOnlyInstalled && content.browsingDefault) {
                    for (const idx of changedIndices) {
                        if (idx < resultsListModel.count) {
                            resultsListModel.set(idx, { payload: content.masterItems[idx] })
                        }
                    }
                }
                content.enrichBatchIndex += content.enrichBatchSize
                if (content.browsingDefault && content.enrichBatchIndex < content.allPackageNames.length) {
                    content.enrichNextBatch()
                } else {
                    content.loadingStatus = ""
                }
            }
        }
    }

    function enrichNextBatch() {
        const batch = content.allPackageNames.slice(content.enrichBatchIndex, content.enrichBatchIndex + content.enrichBatchSize)
        if (batch.length === 0) { content.loadingStatus = ""; return }
        content.loadingStatus = `Loading details ${content.enrichBatchIndex} / ${content.allPackageNames.length}...`
        enrichProc.command = ["pacman", "-Si"].concat(batch)
        enrichProc.running = true
    }

    // NOTE: no longer reads "[installed]" from -Si text (unreliable) -
    // installed status now always comes from content.installedNames
    function parseSiOutput(text) {
        const blocks = text.split(/\n\s*\n/)
        const details = {}
        for (const block of blocks) {
            const nameM = block.match(/^Name\s*:\s*(\S+)/m)
            if (!nameM) continue
            const descM = block.match(/^Description\s*:\s*(.+)$/m)
            const dlM = block.match(/^Download Size\s*:\s*(.+)$/m)
            const instM = block.match(/^Installed Size\s*:\s*(.+)$/m)
            details[nameM[1]] = {
                description: descM ? descM[1].trim() : "",
                meta: (dlM ? "DL: " + dlM[1].trim() : "") + (instM ? "  Inst: " + instM[1].trim() : "")
            }
        }
        return details
    }

    Process {
        id: hiddenLoadProc
        command: ["bash", "-c", "FILE=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/package-installer-hidden.json\"; [ -f \"$FILE\" ] && cat \"$FILE\" || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const names = JSON.parse(text.trim() || "[]")
                    const set = {}
                    names.forEach(n => set[n] = true)
                    content.hiddenNames = set
                } catch (e) {
                    content.hiddenNames = {}
                }
                content.render()
            }
        }
    }

    Process { id: hiddenSaveProc }

    function hidePackage(name) {
        const updated = Object.assign({}, content.hiddenNames)
        updated[name] = true
        content.hiddenNames = updated
        const namesArray = Object.keys(updated)
        const b64 = Qt.btoa(JSON.stringify(namesArray))
        hiddenSaveProc.command = ["bash", "-c", `FILE="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/package-installer-hidden.json"; mkdir -p "$(dirname "$FILE")"; echo '${b64}' | base64 -d > "$FILE"`]
        hiddenSaveProc.running = true
        content.render()
    }

    Component.onCompleted: {
        content.loadingStatus = "Loading installed package list..."
        installedListProc.running = true
        explicitListProc.running = true
        foreignListProc.running = true
        baseGroupProc.running = true
        hiddenLoadProc.running = true
        nameListProc.running = true
    }

    // ------------------------------------------------------------
    // SEARCH MODE
    // ------------------------------------------------------------
    property var pendingRepoResults: []
    property var pendingAurResults: []
    property bool repoDone: false
    property bool aurDone: false

    Process {
        id: pacmanSearchProc
        stdout: StdioCollector {
            onStreamFinished: {
                content.pendingRepoResults = content.parsePacmanOutput(text)
                if (content.pendingRepoResults.length > 0) {
                    searchSizeLookupProc.command = ["pacman", "-Si"].concat(content.pendingRepoResults.map(p => p.name))
                    searchSizeLookupProc.running = true
                } else {
                    content.repoDone = true
                    content.maybeFinalizeSearch()
                }
            }
        }
    }

    Process {
        id: searchSizeLookupProc
        stdout: StdioCollector {
            onStreamFinished: {
                const details = content.parseSiOutput(text)
                content.pendingRepoResults = content.pendingRepoResults.map(pkg => {
                    if (details[pkg.name]) {
                        pkg.meta = details[pkg.name].meta
                        pkg.description = details[pkg.name].description || pkg.description
                    }
                    return pkg
                })
                content.repoDone = true
                content.maybeFinalizeSearch()
            }
        }
    }

    Process {
        id: aurSearchProc
        stdout: StdioCollector {
            onStreamFinished: {
                content.pendingAurResults = content.parseAurOutput(text)
                content.aurDone = true
                content.maybeFinalizeSearch()
            }
        }
    }

    function maybeFinalizeSearch() {
        if (!content.repoDone || !content.aurDone) return
        const combined = content.pendingRepoResults.concat(content.pendingAurResults)
        combined.forEach(item => { item.installed = !!content.installedNames[item.name] })
        const sorted = content.sortResults(combined, content.lastQuery)
        content.masterItems = sorted
        content.render()
        content.pendingRepoResults = []
        content.pendingAurResults = []
        content.repoDone = false
        content.aurDone = false
        content.searching = false
    }

    function sortResults(items, query) {
        const q = query.toLowerCase()
        function scoreOf(item) {
            const name = item.name.toLowerCase()
            const exact = (name === q) ? 1 : 0
            const starts = name.startsWith(q) ? 1 : 0
            const repoBonus = (item.source === "Repo" && starts) ? 1 : 0
            const votes = (item.source === "AUR") ? parseInt(item.meta) || 0 : 0
            return { exact, starts, repoBonus, votes, negLength: -name.length }
        }
        return items.slice().sort((a, b) => {
            const sa = scoreOf(a), sb = scoreOf(b)
            if (sa.exact !== sb.exact) return sb.exact - sa.exact
            if (sa.votes !== sb.votes) return sb.votes - sa.votes
            if (sa.starts !== sb.starts) return sb.starts - sa.starts
            if (sa.repoBonus !== sb.repoBonus) return sb.repoBonus - sa.repoBonus
            return sb.negLength - sa.negLength
        })
    }

    function performSearch(query) {
        if (content.showOnlyInstalled) {
            content.render()
            return
        }
        if (query.length === 0) {
            content.browsingDefault = true
            content.lastQuery = ""
            content.masterItems = content.allPackageNames.map(name => ({
                source: "Repo", name: name, version: "", installed: !!content.installedNames[name],
                description: "", meta: ""
            }))
            content.render()
            content.enrichBatchIndex = 0
            content.enrichNextBatch()
            return
        }
        if (query === content.lastQuery) return
        content.browsingDefault = false
        content.lastQuery = query
        content.searching = true
        content.armedAction = null
        pacmanSearchProc.command = ["pacman", "-Ss", query]
        pacmanSearchProc.running = true
        aurSearchProc.command = ["yay", "-Ss", "--aur", query]
        aurSearchProc.running = true
    }

    // ------------------------------------------------------------
    // Render: rebuild the visible ListModel from masterItems, applying
    // the installed-only filter if active. This is the ONLY place that
    // writes to resultsListModel now.
    // ------------------------------------------------------------
    property real pendingScrollRestore: -1

    function render() {
        content.pendingScrollRestore = resultsList.contentY
        resultsListModel.clear()
        // "Installed only" now uses its own independent dataset (built from
        // pacman -Qi, covering AUR-origin packages too) instead of filtering
        // the repo-only browse list, which structurally could never include
        // AUR-installed apps like spotify/slack/vscode/burpsuite.
        const q = searchField.text.trim().toLowerCase()
        const items = content.showOnlyInstalled
            ? content.installedViewItems.filter(i => !content.hiddenNames[i.name] &&
                (q.length === 0 || i.name.toLowerCase().includes(q) || i.description.toLowerCase().includes(q)))
            : content.masterItems
        items.forEach(pkg => resultsListModel.append({ payload: pkg }))
        if (content.pendingScrollRestore >= 0) {
            const restoreY = content.pendingScrollRestore
            content.pendingScrollRestore = -1
            Qt.callLater(() => { resultsList.contentY = restoreY })
        }
    }

    // ------------------------------------------------------------
    // Actions - install / uninstall / update-system, all via the same
    // arm-and-confirm click pattern, all via floating terminal so
    // sudo/yay can prompt for password natively (proven pattern).
    // ------------------------------------------------------------
    function terminalSizeArgs() {
        const w = Math.round(Screen.width * 0.7 * 0.95)
        const h = Math.round(Screen.height * 0.75 * 0.95)
        return ["-w", w + "x" + h]
    }

    function rowActionType(pkg) {
        return pkg.installed ? "uninstall" : "install"
    }

    function handleRowClick(pkg) {
        const type = content.rowActionType(pkg)
        const key = pkg.source + ":" + pkg.name
        if (content.armedAction && content.armedAction.type === type && content.armedAction.key === key) {
            armDisarmTimer.stop()
            content.runRowAction(pkg, type)
        } else {
            content.armedAction = { type: type, key: key }
            armDisarmTimer.restart()
        }
    }

    function runRowAction(pkg, type) {
        let cmd
        if (type === "uninstall") {
            // Removal is the same regardless of original source (repo or AUR)
            cmd = `sudo pacman -Rns ${pkg.name}`
        } else if (pkg.source === "AUR") {
            cmd = `yay -S --needed ${pkg.name}`
        } else {
            cmd = `sudo pacman -S --needed ${pkg.name}`
        }
        Quickshell.execDetached([
            "foot", "-a", "pkg-installer-term"
        ].concat(content.terminalSizeArgs()).concat([
            "-e", "bash", "-c", cmd + "; echo; read -p 'Press enter to close...'"
        ]))
        content.armedAction = null
        GlobalStates.packageInstallerOpen = false
    }

    function handleUpdateClick() {
        const key = "system"
        if (content.armedAction && content.armedAction.type === "update" && content.armedAction.key === key) {
            armDisarmTimer.stop()
            Quickshell.execDetached([
                "foot", "-a", "pkg-installer-term"
            ].concat(content.terminalSizeArgs()).concat([
                "-e", "bash", "-c", "yay -Syu; echo; read -p 'Press enter to close...'"
            ]))
            content.armedAction = null
            GlobalStates.packageInstallerOpen = false
        } else {
            content.armedAction = { type: "update", key: key }
            armDisarmTimer.restart()
        }
    }

    function parsePacmanOutput(text) {
        const lines = text.split("\n")
        const results = []
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^(\S+)\/(\S+)\s+(\S+)/)
            if (m) {
                const desc = (i + 1 < lines.length) ? lines[i + 1].trim() : ""
                results.push({ source: "Repo", name: m[2], version: m[3], installed: false, description: desc, meta: "..." })
            }
        }
        return results
    }

    function parseAurOutput(text) {
        const lines = text.split("\n")
        const results = []
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^aur\/(\S+)\s+(\S+)(?:\s+\(\+(\d+)\s+[\d.]+\))?/)
            if (m) {
                const desc = (i + 1 < lines.length) ? lines[i + 1].trim() : ""
                results.push({ source: "AUR", name: m[1], version: m[2], installed: false, description: desc, meta: (m[3] ? m[3] : "0") })
            }
        }
        return results
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        RowLayout {
            spacing: 8
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search packages (repo + AUR)... leave empty to browse all")
                focus: true
                onTextChanged: searchDebounce.restart()
                Keys.onReturnPressed: {
                    if (resultsListModel.count > 0) content.handleRowClick(resultsListModel.get(0).payload)
                }
            }
            ComboBox {
                model: [Translation.tr("All"), Translation.tr("Installed only")]
                currentIndex: content.showOnlyInstalled ? 1 : 0
                onCurrentIndexChanged: {
                    content.showOnlyInstalled = (currentIndex === 1)
                    if (content.showOnlyInstalled) {
                        content.render()
                    } else {
                        // Switching to "All" needs a fresh search against
                        // repo+AUR for whatever's currently typed - render()
                        // alone would just redisplay stale masterItems rather
                        // than fetching results for the current query.
                        content.lastQuery = ""
                        content.performSearch(searchField.text.trim())
                    }
                }
            }
            RippleButton {
                buttonText: content.armedAction && content.armedAction.type === "update"
                    ? Translation.tr("Click again to confirm update")
                    : Translation.tr("Update System")
                onClicked: content.handleUpdateClick()
            }
        }

        StyledText {
            visible: content.searching
            text: Translation.tr("Searching...")
            color: Appearance.colors.colOnLayer2
        }

        StyledText {
            visible: content.loadingStatus.length > 0 && !content.showOnlyInstalled
            text: content.loadingStatus
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer2
        }

        Timer { id: searchDebounce; interval: 350; repeat: false; onTriggered: content.performSearch(searchField.text.trim()) }

        ListView {
            id: resultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: resultsListModel
            spacing: 4

            delegate: Rectangle {
                width: resultsList.width
                height: 64
                radius: Appearance.rounding.small
                required property var payload
                property bool isArmed: content.armedAction && content.armedAction.type === content.rowActionType(payload) && content.armedAction.key === (payload.source + ":" + payload.name)
                color: isArmed ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2

                RowLayout {
                    z: 10
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Rectangle {
                        width: 46; height: 22; radius: 6
                        color: payload.source === "AUR" ? "#fab387" : "#a6e3a1"
                        StyledText {
                            anchors.centerIn: parent
                            text: payload.source
                            font.pixelSize: 11
                            font.bold: true
                            color: "#1e1e2e"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 8
                            StyledText { text: payload.name; font.bold: true; color: Appearance.m3colors.m3onSurface }
                            StyledText {
                                visible: payload.version.length > 0
                                text: payload.version
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                visible: payload.installed
                                text: Translation.tr("[installed]")
                                color: "#a6e3a1"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        StyledText {
                            text: payload.description
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            visible: payload.source === "Repo"
                            text: payload.meta
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            visible: payload.source === "AUR"
                            text: content.showOnlyInstalled ? payload.meta : (payload.meta + " votes")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                    }

                    StyledText {
                        visible: isArmed
                        text: payload.installed ? Translation.tr("Click again to uninstall") : Translation.tr("Click again to install")
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "#1e1e2e"
                    }

                    RippleButton {
                        z: 10
                        visible: content.showOnlyInstalled
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        onClicked: content.hidePackage(payload.name)
                        contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 16; color: Appearance.colors.colOnLayer2; text: "close" }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: content.handleRowClick(payload)
                }
            }
        }
    }
}
