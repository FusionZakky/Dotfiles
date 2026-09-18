//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.ii.sidebarLeft.anime

ApplicationWindow {
    id: root
    visible: true
    title: Translation.tr("Wallpaper Picker")
    minimumWidth: 900
    minimumHeight: 600
    width: 1100
    height: 720
    color: Appearance.m3colors.m3background

    property int currentTab: 0
    property string searchProvider: "wallhaven"
    property string searchMode: "single" // "single" | "realistic" | "anime" | "all"
    property var searchResults: []
    property int currentPage: 1
    property real minDesktopAspect: 1.2
    property int minHeightPx: 1080
    property string wallpaperDir: `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers`
    property string previewCacheDir: FileUtils.trimFileProtocol(Directories.booruPreviews)

    property bool showSafe: true
    property bool showQuestionable: false
    property bool showExplicit: false
    property int searchGeneration: 0
    property bool stateLoaded: false
    property var activeXhrs: []
    property bool sessionAuthorized: false
    property var lastRealSearchResults: []
    property var surpriseHistory: []
    property real pendingScrollRestore: -1
    property var apiKeys: ({}) // loaded from our own dedicated file, NOT illogical-impulse's config.json

    // Zerochan/waifu.im/Alcy are all explicitly SFW-only per their own docs - genuinely
    // safe additions, not explicit-focused. Danbooru/Gelbooru removed per your call.
    readonly property var generalProviders: ["wallhaven", "unsplash", "pexels"]
    readonly property var animeProviders: ["yandere", "konachan", "waifu.im", "t.alcy.cc"] // zerochan removed - blocked by an anti-bot JS challenge, not fixable via simple HTTP requests

    function currentProviderList() {
        if (root.searchMode === "single") return [root.searchProvider]
        if (root.searchMode === "realistic") return root.generalProviders
        if (root.searchMode === "anime") return root.animeProviders
        return root.generalProviders.concat(root.animeProviders)
    }

    readonly property var localProviderInfo: ({
        "unsplash": { name: "Unsplash", description: Translation.tr("Real photography | Curated, high quality, requires photographer credit") },
        "pexels": { name: "Pexels", description: Translation.tr("Real photography | Large library, good quality") }
    })
    function providerDisplayName(provider) {
        return (provider in root.localProviderInfo) ? root.localProviderInfo[provider].name : (Booru.providers[provider]?.name ?? provider)
    }
    function providerDescription(provider) {
        return (provider in root.localProviderInfo) ? root.localProviderInfo[provider].description : (Booru.providers[provider]?.description ?? "")
    }

    readonly property var animeTagAliases: ({
        "anime": "", "girl": "1girl", "girls": "1girl", "boy": "1boy", "boys": "1boy",
        "woman": "1girl", "women": "1girl", "man": "1boy", "men": "1boy"
    })
    function normalizeAnimeQuery(query) {
        return query.split(/\s+/).filter(w => w.length > 0).map(w => {
            const lower = w.toLowerCase()
            return (lower in root.animeTagAliases) ? root.animeTagAliases[lower] : w
        }).filter(w => w.length > 0).join(" ")
    }

    function ratingTagSuffix(provider) {
        let tiers = []
        if (root.showSafe) tiers.push("safe")
        if (root.showQuestionable) tiers.push("questionable")
        if (root.showExplicit) tiers.push("explicit")
        if (tiers.length === 0) tiers = ["safe"]
        if (tiers.length === 3) return ""
        if (tiers.length === 1) return " rating:" + tiers[0]
        const allTiers = ["safe", "questionable", "explicit"]
        const missing = allTiers.find(t => !tiers.includes(t))
        return " -rating:" + missing
    }

    // --- Content unlock (unchanged) ---
    Process {
        id: fileBrowseProc
        command: ["kdialog", "--getopenfilename", "--multiple", "--separate-output", FileUtils.trimFileProtocol(Directories.pictures)]
        stdout: StdioCollector {
            onStreamFinished: {
                text.trim().split("\n").filter(l => l.length > 0).forEach(path => root.importLocalFile(path))
            }
        }
    }
    Process {
        id: authProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.sessionAuthorized = true
            else console.log("[WallpaperPicker] auth cancelled/failed")
        }
    }
    function requestUnlock() {
        authProc.command = ["pkexec", "true"]
        authProc.running = true
    }

    // --- Own dedicated API key file - deliberately NOT part of illogical-impulse's
    // config.json, since that file's schema silently strips fields it doesn't
    // recognize (confirmed: our earlier wallhaven/unsplash/pexels keys were wiped by
    // exactly this). This file is fully ours, nothing else touches it.
    Process {
        id: keysLoadProc
        command: ["bash", "-c", "KEYS_FILE=\"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/wallpaper-picker-keys.json\"; [ -f \"$KEYS_FILE\" ] && cat \"$KEYS_FILE\" || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.apiKeys = JSON.parse(text.trim() || "{}") } catch (e) { root.apiKeys = {}; console.log("[WallpaperPicker] key file parse error:", e) }
            }
        }
    }

    // --- Session persistence (unchanged) ---
    Process {
        id: stateLoadProc
        command: ["bash", "-c", "STATE_FILE=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-picker-state.json\"; [ -f \"$STATE_FILE\" ] && cat \"$STATE_FILE\" || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text.trim() || "{}")
                    if (s.searchProvider) root.searchProvider = s.searchProvider
                    if (s.searchMode) root.searchMode = s.searchMode
                    if (typeof s.showSafe === "boolean") root.showSafe = s.showSafe
                    if (s.minHeightPx) root.minHeightPx = s.minHeightPx
                } catch (e) {
                    console.log("[WallpaperPicker] state load parse error (ok on first run):", e)
                }
                root.stateLoaded = true
            }
        }
    }
    Process { id: stateSaveProc }
    Timer { id: stateSaveDebounce; interval: 800; repeat: false; onTriggered: root.saveState() }
    function saveState() {
        if (!root.stateLoaded) return
        const s = {
            searchProvider: root.searchProvider, searchMode: root.searchMode,
            showSafe: root.showSafe, minHeightPx: root.minHeightPx
        }
        const b64 = Qt.btoa(JSON.stringify(s))
        stateSaveProc.command = ["bash", "-c", `STATE_FILE="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-picker-state.json"; mkdir -p "$(dirname "$STATE_FILE")"; echo '${b64}' | base64 -d > "$STATE_FILE"`]
        stateSaveProc.running = true
    }
    function scheduleSave() { stateSaveDebounce.restart() }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        Wallpapers.load();
        stateLoadProc.running = true
        keysLoadProc.running = true
    }
    onClosing: Qt.quit()

    function mapUnsplash(response) {
        return (response.results || []).map(item => ({
            id: item.id, width: item.width, height: item.height,
            aspect_ratio: item.width / item.height,
            tags: item.alt_description || item.description || "",
            rating: "s", is_nsfw: false, md5: item.id,
            preview_url: item.urls.small, sample_url: item.urls.regular,
            file_url: item.urls.full, file_ext: "jpg",
            source: item.user?.links?.html ?? "",
            __provider: "unsplash",
            __attribution: item.user?.name ? `Photo by ${item.user.name} on Unsplash` : "Unsplash",
            __downloadLocation: item.links?.download_location ?? ""
        }))
    }
    function mapPexels(response) {
        return (response.photos || []).map(item => ({
            id: item.id, width: item.width, height: item.height,
            aspect_ratio: item.width / item.height,
            tags: item.alt || "", rating: "s", is_nsfw: false, md5: `${item.id}`,
            preview_url: item.src.medium, sample_url: item.src.large,
            file_url: item.src.original, file_ext: "jpg",
            source: item.photographer_url ?? item.url ?? "",
            __provider: "pexels",
            __attribution: item.photographer ? `Photo by ${item.photographer} on Pexels` : "Pexels"
        }))
    }
    function mapProviderResponse(provider, parsed) {
        if (provider === "unsplash") return root.mapUnsplash(parsed)
        if (provider === "pexels") return root.mapPexels(parsed)
        return Booru.providers[provider].mapFunc(parsed)
    }
    // Alcy is the one exception - its API returns a plain newline-separated list of
    // image URLs, not JSON, so it needs its own non-JSON path entirely.
    function parseAndMap(provider, responseText) {
        if (provider === "t.alcy.cc") {
            return { mapped: Booru.providers["t.alcy.cc"].manualParseFunc(responseText), parsed: null }
        }
        const parsed = JSON.parse(responseText)
        return { mapped: root.mapProviderResponse(provider, parsed), parsed }
    }

    function buildGenericBooruUrl(provider, query, limit, page) {
        const p = Booru.providers[provider]
        let tagString = root.normalizeAnimeQuery(query) + root.ratingTagSuffix(provider)
        let params = []
        params.push("tags=" + encodeURIComponent(tagString))
        params.push("limit=" + limit)
        params.push("page=" + page)
        let url = p.api
        url += (url.indexOf("?") === -1 ? "?" : "&") + params.join("&")
        return url
    }

    function buildSearchUrl(provider, query, page) {
        if (provider === "wallhaven") {
            let params = []
            params.push("q=" + encodeURIComponent(query))
            params.push("page=" + page)
            let purityDigits = `${root.showSafe ? 1 : 0}${root.showQuestionable ? 1 : 0}${root.showExplicit ? 1 : 0}`
            if (purityDigits === "000") purityDigits = "100"
            params.push("purity=" + purityDigits)
            params.push("categories=" + (root.searchMode === "anime" || root.searchMode === "all" ? "111" : "100"))
            params.push("sorting=relevance")
            if (root.apiKeys.wallhaven) params.push("apikey=" + root.apiKeys.wallhaven)
            let url = Booru.providers["wallhaven"].api
            url += (url.indexOf("?") === -1 ? "?" : "&") + params.join("&")
            return url
        }
        if (provider === "unsplash") {
            let params = ["query=" + encodeURIComponent(query), "page=" + page, "per_page=30", "orientation=landscape"]
            if (root.apiKeys.unsplash) params.push("client_id=" + root.apiKeys.unsplash)
            return "https://api.unsplash.com/search/photos?" + params.join("&")
        }
        if (provider === "pexels") {
            let params = ["query=" + encodeURIComponent(query), "page=" + page, "per_page=50", "orientation=landscape"]
            return "https://api.pexels.com/v1/search?" + params.join("&")
        }
        if (provider === "zerochan") {
            // Zerochan's public JSON endpoint has no real tag search - the "c" param
            // (labeled "color" in their API) is what the existing sidebar already uses
            // as a de facto tag field. Mirroring that proven-working approach exactly.
            let params = ["c=" + encodeURIComponent(query), "l=20", "s=fav", "t=1", "p=" + page]
            return Booru.providers["zerochan"].api + "&" + params.join("&")
        }
        if (provider === "waifu.im") {
            let params = []
            query.split(/\s+/).filter(w => w.length > 0).forEach(tag => params.push("IncludedTags=" + encodeURIComponent(tag.toLowerCase())))
            params.push("PageSize=" + 30)
            params.push("IsNsfw=" + ((root.showQuestionable || root.showExplicit) ? "All" : "False"))
            // Note: waifu.im's API doesn't cleanly support offset pagination the way
            // others do, so "load more" may return the same set again for this source.
            return Booru.providers["waifu.im"].api + "?" + params.join("&")
        }
        if (provider === "t.alcy.cc") {
            // Alcy has no free-text search at all - just a handful of fixed category
            // codes (ycy, moez, ysz, fj, bd, xhl). Type one of those as your query.
            const base = Booru.providers["t.alcy.cc"].api
            return base + encodeURIComponent(query) + (base.indexOf("?") === -1 ? "?" : "&") + "json&quantity=20"
        }
        return root.buildGenericBooruUrl(provider, query, 50, page)
    }

    function applyRequestHeaders(xhr, provider) {
        if (provider === "konachan") {
            xhr.setRequestHeader("User-Agent", Booru.defaultUserAgent)
        } else if (provider === "zerochan") {
            const username = Config.options?.sidebar?.booru?.zerochan?.username
            const ua = (username && username !== "[unset]") ? `Desktop sidebar booru viewer - username: ${username}` : Booru.defaultUserAgent
            xhr.setRequestHeader("User-Agent", ua)
        } else if (provider === "pexels") {
            const key = root.apiKeys.pexels
            if (key) xhr.setRequestHeader("Authorization", key)
        }
    }

    function extractTotal(provider, parsed) {
        if (!parsed) return null
        if (provider === "wallhaven" && parsed.meta && typeof parsed.meta.total === "number") return parsed.meta.total
        if (provider === "unsplash" && typeof parsed.total === "number") return parsed.total
        if (provider === "pexels" && typeof parsed.total_results === "number") return parsed.total_results
        return null
    }

    function passesFilters(item) {
        return item.aspect_ratio >= root.minDesktopAspect && item.height >= root.minHeightPx
    }

    function abortActiveRequests() {
        root.activeXhrs.forEach(xhr => { try { xhr.abort() } catch (e) {} })
        root.activeXhrs = []
    }

    function performSearchDispatch() {
        root.currentPage = 1
        root.scheduleSave()
        root.abortActiveRequests()
        root.dispatchSearch(1, false)
    }
    function loadMore() {
        root.pendingScrollRestore = resultsGrid.contentY
        root.currentPage += 1
        root.dispatchSearch(root.currentPage, true)
    }
    function dispatchSearch(page, append) {
        const providers = root.currentProviderList()
        if (providers.length === 1) root.performSearch(providers[0], page, append)
        else root.performAggregateSearch(providers, page, append)
    }
    function restoreScrollIfPending() {
        if (root.pendingScrollRestore >= 0) {
            const restoreY = root.pendingScrollRestore
            root.pendingScrollRestore = -1
            Qt.callLater(() => { resultsGrid.contentY = restoreY })
        }
    }

    function syncResultsToModel(items, append) {
        if (!append) resultsListModel.clear()
        items.forEach(item => resultsListModel.append({ payload: item }))
    }

    function performSearch(provider, page, append) {
        const query = searchField.text.trim()
        if (query.length === 0) { root.searchResults = []; statusText.text = ""; return }
        root.searchGeneration += 1
        const myGeneration = root.searchGeneration
        const url = root.buildSearchUrl(provider, query, page)
        console.log("[WallpaperPicker] Searching:", url)
        const xhr = new XMLHttpRequest()
        root.activeXhrs.push(xhr)
        xhr.open("GET", url)
        root.applyRequestHeaders(xhr, provider)
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (myGeneration !== root.searchGeneration) return
            if (xhr.status === 200) {
                try {
                    const { mapped, parsed } = root.parseAndMap(provider, xhr.responseText)
                    const filtered = mapped.filter(root.passesFilters)
                    root.searchResults = append ? root.searchResults.concat(filtered) : filtered
                    root.lastRealSearchResults = root.searchResults
                    root.syncResultsToModel(filtered, append)
                    const total = root.extractTotal(provider, parsed)
                    statusText.text = total !== null ? `Showing ${root.searchResults.length} of ${total} total` : `Showing ${root.searchResults.length}`
                    if (append) root.restoreScrollIfPending()
                } catch (e) {
                    console.log("[WallpaperPicker] parse error:", e)
                    statusText.text = Translation.tr("Failed to parse response")
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusText.text = Translation.tr("Blocked, needs API key (") + xhr.status + ")"
            } else {
                statusText.text = Translation.tr("Request failed: ") + xhr.status
            }
        }
        xhr.send()
    }

    function performAggregateSearch(providers, page, append) {
        const query = searchField.text.trim()
        if (query.length === 0) { root.searchResults = []; statusText.text = ""; return }
        root.searchGeneration += 1
        const myGeneration = root.searchGeneration
        let localBuffer = []
        let localBreakdown = {}
        let localPending = providers.length
        statusText.text = Translation.tr("Searching %1 source(s)...").arg(providers.length)
        providers.forEach(provider => {
            const url = root.buildSearchUrl(provider, query, page)
            const xhr = new XMLHttpRequest()
            root.activeXhrs.push(xhr)
            xhr.open("GET", url)
            root.applyRequestHeaders(xhr, provider)
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (myGeneration !== root.searchGeneration) return
                let countLabel = "0"
                if (xhr.status === 200) {
                    try {
                        const { mapped, parsed } = root.parseAndMap(provider, xhr.responseText)
                        const filtered = mapped.filter(root.passesFilters)
                        filtered.forEach(item => { item.__provider = provider })
                        localBuffer = localBuffer.concat(filtered)
                        const total = root.extractTotal(provider, parsed)
                        countLabel = total !== null ? `${filtered.length} of ${total}` : `${filtered.length}`
                    } catch (e) { countLabel = "parse error" }
                } else if (xhr.status === 401 || xhr.status === 403) {
                    countLabel = `blocked (${xhr.status})`
                } else {
                    countLabel = `failed (${xhr.status})`
                }
                localBreakdown[provider] = countLabel
                localPending -= 1
                if (localPending <= 0) root.finishAggregateSearch(myGeneration, localBuffer, localBreakdown, append)
            }
            xhr.send()
        })
    }

    function finishAggregateSearch(generation, buffer, breakdown, append) {
        if (generation !== root.searchGeneration) return
        root.searchResults = append ? root.searchResults.concat(buffer) : buffer
        root.lastRealSearchResults = root.searchResults
        root.syncResultsToModel(buffer, append)
        const parts = Object.keys(breakdown).map(p => `${root.providerDisplayName(p)}: ${breakdown[p]}`)
        statusText.text = (root.searchResults.length === 0 ? Translation.tr("No matches (") : Translation.tr("Showing ") + root.searchResults.length + Translation.tr(" — "))
            + (root.searchResults.length === 0 ? parts.join(", ") + ")" : parts.join(", "))
        if (append) root.restoreScrollIfPending()
    }

    function pickWithHistory(list) {
        const unseen = list.filter(item => !root.surpriseHistory.includes(item.file_url))
        const candidates = unseen.length > 0 ? unseen : list
        if (unseen.length === 0) console.log("[WallpaperPicker] Surprise me: all candidates already shown this session, allowing a repeat")
        return candidates[Math.floor(Math.random() * candidates.length)]
    }

    function surpriseMe() {
        if (root.lastRealSearchResults.length > 0) {
            const safeOnly = root.lastRealSearchResults.filter(item => !item.is_nsfw)
            if (safeOnly.length > 0) {
                root.showSurprisePick(root.pickWithHistory(safeOnly))
                return
            }
            console.log("[WallpaperPicker] Surprise me: current results have no safe items, falling back to a fresh safe fetch")
        }
        root.surpriseFreshFetch()
    }

    function surpriseFreshFetch() {
        const providers = root.currentProviderList()
        const provider = providers[Math.floor(Math.random() * providers.length)]
        console.log("[WallpaperPicker] Surprise me: fresh safe fetch from", provider)
        let url = ""
        let isUnsplashRandom = false
        if (provider === "wallhaven") {
            const randomPage = 1 + Math.floor(Math.random() * 40)
            let params = [`sorting=toplist`, `topRange=1M`, `purity=100`, `categories=100`, `page=${randomPage}`]
            if (root.apiKeys.wallhaven) params.push("apikey=" + root.apiKeys.wallhaven)
            url = "https://wallhaven.cc/api/v1/search?" + params.join("&")
        } else if (provider === "unsplash") {
            isUnsplashRandom = true
            let params = ["orientation=landscape", "content_filter=high"]
            if (root.apiKeys.unsplash) params.push("client_id=" + root.apiKeys.unsplash)
            url = "https://api.unsplash.com/photos/random?" + params.join("&")
        } else if (provider === "pexels") {
            const randomPage = 1 + Math.floor(Math.random() * 300)
            url = `https://api.pexels.com/v1/curated?per_page=10&page=${randomPage}`
                        } else if (provider === "waifu.im" || provider === "t.alcy.cc") {
            // These three have no meaningful "browse everything safely" mode without a
            // real query - fall back to Konachan/Yande.re logic below instead.
            url = root.buildSearchUrl("konachan", "scenery rating:safe", 1 + Math.floor(Math.random() * 5))
        } else {
            const randomPage = 1 + Math.floor(Math.random() * 5)
            let params = [`tags=${encodeURIComponent("scenery rating:safe")}`, "limit=20", "page=" + randomPage]
            url = Booru.providers[provider].api + (Booru.providers[provider].api.indexOf("?") === -1 ? "?" : "&") + params.join("&")
        }
        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        root.applyRequestHeaders(xhr, provider)
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) { console.log("[WallpaperPicker] surprise fetch failed", provider, xhr.status); return }
            try {
                const mapped = isUnsplashRandom ? root.mapUnsplash({ results: [JSON.parse(xhr.responseText)] }) : root.parseAndMap("konachan", xhr.responseText).mapped
                const safe = mapped.filter(item => !item.is_nsfw).filter(root.passesFilters)
                if (safe.length === 0) { console.log("[WallpaperPicker] surprise fetch: nothing safe passed filters", provider); return }
                root.showSurprisePick(root.pickWithHistory(safe))
            } catch (e) { console.log("[WallpaperPicker] surprise fetch parse error", provider, e) }
        }
        xhr.send()
    }

    function showSurprisePick(pick) {
        console.log("[WallpaperPicker] Surprise pick:", pick.file_url)
        root.surpriseHistory = root.surpriseHistory.concat([pick.file_url])
        root.searchResults = [pick]
        root.syncResultsToModel([pick], false)
        root.currentTab = 1
        statusText.text = Translation.tr("Surprise pick - use the menu to download or set as wallpaper")
        root.previewItem = pick
    }

    function importLocalFile(sourcePath) {
        const escapedSrc = StringUtils.shellSingleQuoteEscape(sourcePath)
        const targetDir = root.wallpaperDir
        const script = `
manifest="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-hashes.txt"
mkdir -p "$(dirname "$manifest")" '${targetDir}'
src='${escapedSrc}'
hash=$(sha256sum "$src" | cut -d' ' -f1)
existing=$(grep "^$hash " "$manifest" 2>/dev/null | head -1 | cut -d' ' -f2-)
if [ -n "$existing" ] && [ -f "$existing" ]; then
    notify-send 'Already in library' "$existing" -a 'Shell'
else
    finalPath="${targetDir}/$(basename "$src")"
    cp "$src" "$finalPath"
    echo "$hash $finalPath" >> "$manifest"
    notify-send 'Added to library' "$finalPath" -a 'Shell'
fi
`.trim()
        Quickshell.execDetached(["bash", "-c", script])
    }

    function deleteLibraryImage(path) {
        const manifest = "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-hashes.txt"
        const escapedPath = StringUtils.shellSingleQuoteEscape(path)
        const script = `
rm -f '${escapedPath}'
manifest="${manifest}"
if [ -f "$manifest" ]; then
    grep -v " '${escapedPath}'$\\|'${escapedPath}'$" "$manifest" > "$manifest.tmp" 2>/dev/null || true
    mv "$manifest.tmp" "$manifest" 2>/dev/null || true
fi
`.trim()
        Quickshell.execDetached(["bash", "-c", script])
        Wallpapers.load()
    }

    property var previewItem: null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        enabled: root.stateLoaded

        RowLayout {
            spacing: 8
            RippleButton { buttonText: Translation.tr("Library"); toggled: root.currentTab === 0; onClicked: root.currentTab = 0 }
            RippleButton { buttonText: Translation.tr("Search"); toggled: root.currentTab === 1; onClicked: root.currentTab = 1 }
            Item { Layout.fillWidth: true }
            StyledText {
                visible: !root.stateLoaded
                font.italic: true
                color: Appearance.colors.colOnLayer2
                text: Translation.tr("Loading last session...")
            }
            StyledText {
                visible: root.stateLoaded && root.currentTab === 1
                font.bold: true
                color: "white"
                text: root.searchMode !== "single"
                    ? (root.searchMode === "realistic" ? Translation.tr("All realistic sources")
                        : root.searchMode === "anime" ? Translation.tr("All anime sources")
                        : Translation.tr("Everything"))
                    : root.providerDescription(root.searchProvider)
            }
            Item { Layout.fillWidth: true }
            StyledText { id: statusText; color: Appearance.colors.colOnLayer1 }
        }

        StackLayout {
            currentIndex: root.currentTab
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8
                    RowLayout {
                        spacing: 8
                        TextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Filter by filename...")
                            onTextChanged: Wallpapers.searchQuery = text
                        }
                        RippleButton {
                            buttonText: Translation.tr("Browse & add...")
                            onClicked: fileBrowseProc.running = true
                        }
                    }
                    DropArea {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        onDropped: (drop) => {
                            drop.urls.forEach(url => root.importLocalFile(FileUtils.trimFileProtocol(url.toString())))
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: parent.containsDrag
                            color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.7)
                            border.width: 2
                            border.color: Appearance.m3colors.m3primary
                            radius: Appearance.rounding.small
                            z: 5
                        }
                        GridView {
                            id: libraryGrid
                            anchors.fill: parent
                            clip: true
                            cellWidth: 220
                            cellHeight: 140
                            model: Wallpapers.wallpapers.filter(path => Wallpapers.extensions.includes(path.split('.').pop().toLowerCase()))
                        delegate: Item {
                            id: libItem
                            width: libraryGrid.cellWidth
                            height: libraryGrid.cellHeight
                            required property var modelData
                            property bool showMenu: false
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                Image { anchors.fill: parent; source: `file://${libItem.modelData}`; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Wallpapers.apply(libItem.modelData) }
                                RippleButton {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                                    colBackgroundHover: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.8), 0.2)
                                    colRipple: ColorUtils.transparentize(ColorUtils.mix(Appearance.m3colors.m3surface, Appearance.m3colors.m3onSurface, 0.6), 0.1)
                                    onClicked: libItem.showMenu = !libItem.showMenu
                                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 18; color: Appearance.m3colors.m3onSurface; text: "more_vert" }
                                }
                            }
                            Rectangle {
                                visible: libItem.showMenu
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 34
                                anchors.rightMargin: 4
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
                                        buttonText: Translation.tr("Preview")
                                        onClicked: { libItem.showMenu = false; root.previewItem = libItem.modelData }
                                    }
                                    MenuButton {
                                        Layout.fillWidth: true
                                        buttonText: Translation.tr("Delete")
                                        onClicked: { libItem.showMenu = false; root.deleteLibraryImage(libItem.modelData) }
                                    }
                                }
                            }
                        }
                        }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        ComboBox {
                            id: providerCombo
                            visible: root.searchMode === "single"
                            model: ["wallhaven", "unsplash", "pexels", "konachan", "yandere", "waifu.im", "t.alcy.cc"]
                            currentIndex: Math.max(0, model.indexOf(root.searchProvider))
                            onCurrentTextChanged: { root.searchProvider = currentText; root.scheduleSave() }
                        }
                        ComboBox {
                            id: modeCombo
                            model: ["Single provider", "All realistic sources", "All anime sources", "Everything"]
                            readonly property var modeValues: ["single", "realistic", "anime", "all"]
                            currentIndex: modeValues.indexOf(root.searchMode)
                            onCurrentIndexChanged: {
                                root.searchMode = modeValues[currentIndex]
                                root.scheduleSave()
                                if (searchField.text.length > 0) root.performSearchDispatch()
                            }
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: root.searchProvider === "t.alcy.cc" ? Translation.tr("Category code: ycy, moez, ysz, fj, bd, xhl") : Translation.tr("Search tags...")
                            onAccepted: { searchDebounce.stop(); root.performSearchDispatch() }
                            onTextChanged: { root.scheduleSave(); if (text.length === 0) { searchDebounce.stop(); return }; searchDebounce.restart() }
                        }
                        Timer { id: searchDebounce; interval: 500; repeat: false; onTriggered: root.performSearchDispatch() }
                        RippleButton { buttonText: Translation.tr("Search"); onClicked: root.performSearchDispatch() }
                        RippleButton { buttonText: Translation.tr("🎲 Surprise me"); onClicked: root.surpriseMe() }
                    }

                    RowLayout {
                        spacing: 10
                        StyledText { font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2; text: Translation.tr("Rating:") }
                        CheckBox {
                            text: Translation.tr("Safe")
                            checked: root.showSafe
                            onClicked: { root.showSafe = checked; root.scheduleSave(); if (searchField.text.length > 0) root.performSearchDispatch() }
                        }
                        RippleButton {
                            visible: !root.sessionAuthorized
                            implicitWidth: 22
                            implicitHeight: 22
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: root.requestUnlock()
                            contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 16; color: "#8b0000"; text: "lock" }
                        }
                        CheckBox {
                            visible: root.sessionAuthorized
                            text: Translation.tr("Questionable")
                            checked: root.showQuestionable
                            onClicked: { root.showQuestionable = checked; root.scheduleSave(); if (searchField.text.length > 0) root.performSearchDispatch() }
                        }
                        CheckBox {
                            visible: root.sessionAuthorized
                            text: Translation.tr("Explicit")
                            checked: root.showExplicit
                            onClicked: { root.showExplicit = checked; root.scheduleSave(); if (searchField.text.length > 0) root.performSearchDispatch() }
                        }
                        StyledText { font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2; text: Translation.tr("Min height (px):") }
                        SpinBox {
                            from: 0; to: 8000; stepSize: 120
                            value: root.minHeightPx
                            onValueChanged: { root.minHeightPx = value; root.scheduleSave() }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ListModel {
                        id: resultsListModel
                        dynamicRoles: true
                    }
                    GridView {
                        id: resultsGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        cellWidth: 260
                        cellHeight: 180
                        clip: true
                        model: resultsListModel
                        onAtYEndChanged: if (atYEnd && resultsListModel.count > 0) root.loadMore()
                        delegate: Item {
                            width: resultsGrid.cellWidth
                            height: resultsGrid.cellHeight
                            required property var payload
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 2
                                BooruImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    property var modelData: parent.parent.payload
                                    imageData: parent.parent.payload
                                    rowHeight: parent.parent.height - 34
                                    manualDownload: true
                                    previewDownloadPath: root.previewCacheDir
                                    downloadPath: root.wallpaperDir
                                    nsfwPath: root.wallpaperDir
                                    downloadTrackingUrl: parent.parent.payload.__downloadLocation ?? ""
                                    onClicked: root.previewItem = parent.parent.payload
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !!parent.parent.payload.__attribution
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    text: parent.parent.payload.__attribution ?? ""
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.previewItem !== null
        color: "#dd000000"
        z: 999
        MouseArea { anchors.fill: parent; onClicked: root.previewItem = null }
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.85
            height: parent.height * 0.85
            fillMode: Image.PreserveAspectFit
            source: root.previewItem ? (typeof root.previewItem === "string" ? ("file://" + root.previewItem) : (root.previewItem.sample_url ?? root.previewItem.file_url)) : ""
            asynchronous: true
        }
        StyledText {
            visible: !!(root.previewItem && root.previewItem.__attribution)
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 16
            color: "white"
            text: root.previewItem ? (root.previewItem.__attribution ?? "") : ""
        }
    }
}
