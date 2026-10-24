import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import QtMultimedia
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.ii.sidebarLeft.anime

Rectangle {
    id: root
    anchors.fill: parent
    color: Appearance.m3colors.m3background
    radius: Appearance.rounding.normal
    clip: true

    property int currentTab: 0
    property string searchProvider: "wallhaven"
    property string searchMode: "single" // "single" | "realistic" | "anime" | "all"
    property var searchResults: []
    property int currentPage: 1
    property real minDesktopAspect: 1.2
    property int minHeightPx: 1080
    property string wallpaperDir: `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers`
    property string previewCacheDir: FileUtils.trimFileProtocol(Directories.booruPreviews)

    property int searchGeneration: 0
    // Wheel scrolling speed, shared by every grid in this panel (Library, Search and SDDM).
    // Change these two numbers and all tabs follow.
    property real wheelMouseStep: 600
    property real wheelTouchpadStep: 400

    // SDDM detail screen state
    property var sddmDetail: null
    property string sddmBusy: ""
    property string sddmActiveName: ""
    property string sddmActivePath: ""
    readonly property bool sddmVideoSupported: true
    // --- Wallhaven browsing: replicates the website's main tabs ---
    property string wallhavenMode: "latest" // "search" | "latest" | "toplist" | "favorites" | "views" | "random"
    property string wallhavenSort: "relevance" // sort order used inside "search" mode
    property string wallhavenTopRange: "1w"
    property string wallhavenSeed: ""
    property string selectedColor: ""
    property string wallhavenCategory: "general" // "general" | "anime" | "both"
    // Extra safety net on top of purity=100: Wallhaven's "SFW" label is assigned by uploaders,
    // so suggestive images do slip through. These are sent as -tag exclusions on every request.
    // Trim or extend freely; set to [] to switch the extra filter off.
    readonly property var wallhavenBlockedTags: ["nude", "nudity", "topless", "lingerie", "underwear", "panties", "bikini", "swimsuit", "cleavage", "boobs", "sideboob", "underboob", "ecchi", "fetish"]
    readonly property bool wallhavenActive: root.searchMode === "single" && root.searchProvider === "wallhaven"
    readonly property var wallhavenColors: [
        "660000","990000","cc0000","cc3333","ea4c88","993399","663399",
        "333399","0066cc","0099cc","66cccc","77cc33","669900","336600",
        "666600","999900","cccc33","ffff00","ffcc33","ff9900","ff6600",
        "cc6633","996633","663300","000000","999999","cccccc","ffffff","424153"
    ]
    property bool stateLoaded: false
    property var activeXhrs: []
    property var lastRealSearchResults: []
    property var surpriseHistory: []
    property real pendingScrollRestore: -1
    property var apiKeys: ({}) // loaded from our own dedicated file, NOT illogical-impulse's config.json

    readonly property var generalProviders: ["wallhaven", "unsplash", "pexels"]

    function currentProviderList() {
        if (root.searchMode === "single") return [root.searchProvider]
        return root.generalProviders
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



    // --- Own dedicated API key file - deliberately NOT part of illogical-impulse's
    // config.json, since that file's schema silently strips fields it doesn't
    // recognize (confirmed: our earlier wallhaven/unsplash/pexels keys were wiped by
    // exactly this). This file is fully ours, nothing else touches it.
    // Largest monitor size, read the same way switchwall.sh reads it
    property int screenW: 0
    property int screenH: 0
    // true: only ask Wallhaven for images that already cover the screen (no "resolution is lower" prompt).
    // Set to false to also see smaller images; they get upscaled automatically when applied.
    property bool wallhavenMatchScreen: false
    // true: show Wallhaven's mid-size thumbnail while the full file downloads (set false if it feels slower)
    property bool wallhavenUseMidThumb: true
    Process {
        id: monitorProc
        command: ["bash", "-c", "hyprctl monitors -j | jq -r '[([.[].width] | max), ([.[].height] | max)] | @tsv'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/).map(Number)
                if (parts.length >= 2 && parts[0] > 0 && parts[1] > 0) {
                    root.screenW = parts[0]
                    root.screenH = parts[1]
                }
            }
        }
    }
    // Upscales (Lanczos) only if the image is smaller than the screen, then applies it
    Process {
        id: fitProc
        property string target: ""
        onExited: Wallpapers.apply(fitProc.target)
    }
    function applyWithFit(path) {
        fitProc.target = path
        fitProc.command = ["bash", "-c", '"$HOME/.config/quickshell/ii/scripts/wallpaper-fit.sh" "$1"', "fit", path]
        fitProc.running = true
    }
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
                    if (s.searchProvider && ["wallhaven", "unsplash", "pexels"].includes(s.searchProvider)) root.searchProvider = s.searchProvider
                    if (s.searchMode === "single" || s.searchMode === "all") root.searchMode = s.searchMode
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
            minHeightPx: root.minHeightPx
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
        monitorProc.running = true
        const rs = GlobalStates.wallpaperPickerResume
        if (rs && rs.tab === 2) { root.currentTab = 2; root.ensureSddmScan() }
    }

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
    function parseAndMap(provider, responseText) {

        const parsed = JSON.parse(responseText)
        const mapped = root.mapProviderResponse(provider, parsed)
        if (provider === "wallhaven" && parsed && Array.isArray(parsed.data)) {
            mapped.forEach((m, i) => { m.__midUrl = parsed.data[i]?.thumbs?.original ?? "" })
        }
        return { mapped, parsed }
    }



    function wallhavenBlockTerms() {
        return root.wallhavenBlockedTags.map(t => "-" + (t.indexOf(" ") >= 0 ? '"' + t + '"' : t))
    }

    function wallhavenCategoryBits() {
        if (root.wallhavenCategory === "anime") return "010"
        if (root.wallhavenCategory === "both") return "110"
        return "100"
    }

    function wallhavenSortingFor(mode, hasQuery) {
        if (mode === "latest") return "date_added"
        if (mode === "toplist") return "toplist"
        if (mode === "favorites") return "favorites"
        if (mode === "views") return "views"
        if (mode === "random") return "random"
        // "search": relevance only means something when there is a query
        if (root.wallhavenSort === "relevance" && !hasQuery) return "date_added"
        return root.wallhavenSort
    }

    function buildSearchUrl(provider, query, page) {
        if (provider === "wallhaven") {
            // Aggregate modes always behave like a normal tag search
            const mode = (root.searchMode === "single") ? root.wallhavenMode : "search"
            const hasQuery = query.length > 0
            let params = []
            let qParts = []
            if (mode === "search" && hasQuery) qParts.push(query)
            qParts = qParts.concat(root.wallhavenBlockTerms())
            if (qParts.length > 0) params.push("q=" + encodeURIComponent(qParts.join(" ")))
            params.push("page=" + page)
            params.push("purity=100") // safe only, always
            params.push("categories=" + root.wallhavenCategoryBits())
            params.push("sorting=" + root.wallhavenSortingFor(mode, hasQuery))
            params.push("order=desc")
            if (root.wallhavenMatchScreen && root.screenW > 0 && root.screenH > 0) params.push("atleast=" + root.screenW + "x" + root.screenH)
            if (mode === "toplist") params.push("topRange=" + root.wallhavenTopRange)
            if (root.searchMode === "single" && root.selectedColor.length > 0) params.push("colors=" + root.selectedColor)
            if (mode === "random" && page > 1 && root.wallhavenSeed.length > 0) params.push("seed=" + root.wallhavenSeed)
            if (root.apiKeys.wallhaven) params.push("apikey=" + root.apiKeys.wallhaven)
            let url = Booru.providers["wallhaven"].api
            url += (url.indexOf("?") === -1 ? "?" : "&") + params.join("&")
            return url
        }
        if (provider === "unsplash") {
            let params = ["query=" + encodeURIComponent(query), "page=" + page, "per_page=30", "orientation=landscape", "content_filter=high"]
            if (root.apiKeys.unsplash) params.push("client_id=" + root.apiKeys.unsplash)
            return "https://api.unsplash.com/search/photos?" + params.join("&")
        }
        if (provider === "pexels") {
            let params = ["query=" + encodeURIComponent(query), "page=" + page, "per_page=50", "orientation=landscape"]
            return "https://api.pexels.com/v1/search?" + params.join("&")
        }



        return ""
    }

    function applyRequestHeaders(xhr, provider) {
        if (provider === "pexels") {
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

    function setWallhavenMode(mode) {
        root.wallhavenMode = mode
        if (mode !== "search") searchField.text = ""
        root.performSearchDispatch()
    }
    function ensureInitialBrowse() {
        if (root.wallhavenActive && root.searchResults.length === 0 && searchField.text.trim().length === 0)
            root.performSearchDispatch()
    }

    function performSearchDispatch() {
        root.currentPage = 1
        root.scheduleSave()
        root.abortActiveRequests()
        root.wallhavenSeed = ""
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
        if (query.length === 0 && provider !== "wallhaven") { root.searchResults = []; statusText.text = ""; return }
        root.searchGeneration += 1
        const myGeneration = root.searchGeneration
        const url = root.buildSearchUrl(provider, query, page)
        console.log("[WallpaperPicker] Searching:", url.replace(/(apikey|client_id)=[^&]+/g, "$1=***"))
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
                    filtered.forEach(item => { item.__provider = provider })
                    root.searchResults = append ? root.searchResults.concat(filtered) : filtered
                    root.lastRealSearchResults = root.searchResults
                    root.syncResultsToModel(filtered, append)
                    const total = root.extractTotal(provider, parsed)
                    if (provider === "wallhaven" && parsed && parsed.meta && parsed.meta.seed) root.wallhavenSeed = parsed.meta.seed
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
        let surpriseProvider = provider
        if (provider === "wallhaven") {
            const randomPage = 1 + Math.floor(Math.random() * 40)
            let params = [`sorting=toplist`, `topRange=1M`, `purity=100`, `categories=${root.wallhavenCategoryBits()}`, `page=${randomPage}`]
            if (root.wallhavenBlockedTags.length > 0) params.push("q=" + encodeURIComponent(root.wallhavenBlockTerms().join(" ")))
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
                        }
        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        root.applyRequestHeaders(xhr, provider)
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) { console.log("[WallpaperPicker] surprise fetch failed", provider, xhr.status); return }
            try {
                const mapped = isUnsplashRandom ? root.mapUnsplash({ results: [JSON.parse(xhr.responseText)] }) : root.parseAndMap(surpriseProvider, xhr.responseText).mapped
                mapped.forEach(item => { item.__provider = surpriseProvider })
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

    function importAndApplyLocalFile(sourcePath) {
        const escapedSrc = StringUtils.shellSingleQuoteEscape(sourcePath)
        const targetDir = root.wallpaperDir
        const script = `
manifest="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-hashes.txt"
mkdir -p "$(dirname "$manifest")" '${targetDir}'
src='${escapedSrc}'
hash=$(sha256sum "$src" | cut -d' ' -f1)
existing=$(grep "^$hash " "$manifest" 2>/dev/null | head -1 | cut -d' ' -f2-)
if [ -n "$existing" ] && [ -f "$existing" ]; then
    finalPath="$existing"
    notify-send 'Already in library' "$finalPath" -a 'Shell'
else
    finalPath="${targetDir}/$(basename "$src")"
    cp "$src" "$finalPath"
    echo "$hash $finalPath" >> "$manifest"
    notify-send 'Copied and set as wallpaper' "$finalPath" -a 'Shell'
fi
"$HOME/.config/quickshell/ii/scripts/wallpaper-fit.sh" "$finalPath" || true
qs -c ii ipc call wallpapers apply "$finalPath"
`.trim()
        Quickshell.execDetached(["bash", "-c", script])
    }

    function selectLibraryImage(filePath) {
        // Always copy (never move/delete the original) when the source lives outside
        // the managed Wallpapers folder - only apply directly when it's already there.
        const currentDir = FileUtils.trimFileProtocol(Wallpapers.effectiveDirectory).replace(/\/+$/, "")
        const targetDir = root.wallpaperDir.replace(/\/+$/, "")
        if (currentDir === targetDir) {
            root.applyWithFit(filePath)
        } else {
            root.importAndApplyLocalFile(filePath)
        }
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

    function toggleTag(tag) {
        if (root.selectedPreviewTags.indexOf(tag) >= 0)
            root.selectedPreviewTags = root.selectedPreviewTags.filter(t => t !== tag)
        else
            root.selectedPreviewTags = root.selectedPreviewTags.concat([tag])
    }

    function searchSelectedTags() {
        if (root.selectedPreviewTags.length === 0) return
        // "+tag" is Wallhaven's exact-match operator; multi-word tags need quotes
        const q = root.selectedPreviewTags.map(t => (t.indexOf(" ") >= 0 ? '+"' + t + '"' : "+" + t)).join(" ")
        root.previewItem = null
        root.currentTab = 1
        if (root.searchMode !== "single") root.searchMode = "single"
        if (root.searchProvider !== "wallhaven") root.searchProvider = "wallhaven"
        root.wallhavenMode = "search"
        searchDebounce.stop()
        searchField.text = q
        searchDebounce.stop()
        root.performSearchDispatch()
    }

    function fetchPreviewTags(item) {
        root.previewTags = []
        root.selectedPreviewTags = []
        if (!item || typeof item !== "object" || item.__provider !== "wallhaven" || !item.id) return
        root.previewTagsLoading = true
        let params = []
        if (root.apiKeys.wallhaven) params.push("apikey=" + root.apiKeys.wallhaven)
        const url = `https://wallhaven.cc/api/v1/w/${item.id}` + (params.length ? "?" + params.join("&") : "")
        const xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            root.previewTagsLoading = false
            if (xhr.status === 200) {
                try {
                    const parsed = JSON.parse(xhr.responseText)
                    const tags = (parsed.data?.tags || []).map(t => t.name)
                    if (root.previewItem === item) root.previewTags = tags
                } catch (e) { console.log("[WallpaperPicker] tag fetch parse error", e) }
            }
        }
        xhr.send()
    }

    function downloadAndApplyRemote(item, applyAfter) {
        if (!item || typeof item !== "object") return
        const userAgent = Config.options?.networking?.userAgent ?? ""
        const uaHeader = userAgent ? ` -H 'User-Agent: ${StringUtils.shellSingleQuoteEscape(userAgent)}'` : ""
        const url = StringUtils.shellSingleQuoteEscape(item.file_url)
        const fileName = decodeURIComponent(item.file_url.split('?')[0].split('/').pop())
        const targetDir = root.wallpaperDir
        const applyCmd = applyAfter ? ` && qs -c ii ipc call wallpapers apply "$finalPath"` : ""
        const fitCmd = applyAfter ? '\n"$HOME/.config/quickshell/ii/scripts/wallpaper-fit.sh" "$finalPath" || true' : ""
        const script = `
manifest="\${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/wallpaper-hashes.txt"
mkdir -p "$(dirname "$manifest")" '${targetDir}'
tmpFile=$(mktemp)
curl -sL '${url}'${uaHeader} -o "$tmpFile"
hash=$(sha256sum "$tmpFile" | cut -d' ' -f1)
existing=$(grep "^$hash " "$manifest" 2>/dev/null | head -1 | cut -d' ' -f2-)
if [ -n "$existing" ] && [ -f "$existing" ]; then
    finalPath="$existing"
    rm -f "$tmpFile"
    notify-send '${Translation.tr("Already downloaded")}' "$finalPath" -a 'Shell'
else
    finalPath="${targetDir}/${fileName}"
    mv "$tmpFile" "$finalPath"
    echo "$hash $finalPath" >> "$manifest"
    notify-send '${Translation.tr("Download complete")}' "$finalPath" -a 'Shell'
fi${fitCmd}${applyCmd}
`.trim()
        Quickshell.execDetached(["bash", "-c", script])
    }

    // ---------------- Glass tab: live HyprGlass tuning (backend: scripts/hyprglass_ctl.py) ----------------
    property string gRgb: "#350015"
    property real gAlpha: 40
    property real gOpacity: 80
    property real gBlur: 1.5
    property real gBrightness: 82
    property real gHue: 0.94
    property real gSat: 1
    property real gVal: 0.33
    property bool gAuto: false
    property bool gPlugin: false
    property bool gLoaded: false
    property bool gDragging: false
    property bool gDirty: false
    property string gStatus: ""
    property string gWallpaper: ""
    property var gPresets: []
    property var gPalette: []
    readonly property string glassCtl: Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/hyprglass_ctl.py"

    function glassHex2(v) {
        const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    function glassRgbHex(c) { return ("#" + root.glassHex2(c.r) + root.glassHex2(c.g) + root.glassHex2(c.b)).toUpperCase() }
    function glassSetRgb(hex) {
        try {
            const c = Qt.color(hex)
            root.gRgb = root.glassRgbHex(c)
            if (c.hsvHue >= 0) root.gHue = c.hsvHue
            root.gSat = c.hsvSaturation
            root.gVal = c.hsvValue
        } catch (e) { console.log("[WallpaperPicker] bad glass colour:", hex) }
    }
    function glassSetHsv(h, s, v) {
        root.gHue = h; root.gSat = s; root.gVal = v
        root.gRgb = root.glassRgbHex(Qt.hsva(h, s, v, 1))
        root.glassQueueApply()
    }
    function glassCurrent() {
        return { rgb: root.gRgb, alpha: Math.round(root.gAlpha), opacity: Math.round(root.gOpacity), blur: Math.round(root.gBlur * 10) / 10, brightness: Math.round(root.gBrightness) }
    }
    function glassUse(s) {
        root.glassSetRgb(s.rgb); root.gAlpha = s.alpha; root.gOpacity = s.opacity; root.gBlur = s.blur; root.gBrightness = s.brightness
    }
    function glassApplySettings(s) { root.glassUse(s); root.glassQueueApply() }
    function glassReset() { root.glassApplySettings({ rgb: "#350015", alpha: 40, opacity: 80, blur: 1.5, brightness: 82 }) }
    function glassHexEntered(t) {
        let v = String(t).trim()
        if (!v.startsWith("#")) v = "#" + v
        if (/^#[0-9a-fA-F]{6}$/.test(v)) { root.glassSetRgb(v); root.glassQueueApply() }
        else root.gStatus = Translation.tr("Enter a six-digit hex colour, for example #350015")
    }
    function glassQueueApply() { glassApplyTimer.restart() }

    Timer { id: glassApplyTimer; interval: 160; onTriggered: root.glassApplyNow() }
    Timer { interval: 3000; repeat: true; running: root.currentTab === 3 && root.gAuto && !root.gDragging; onTriggered: root.glassRefresh() }

    Process {
        id: glassApplyProc
        stdout: StdioCollector { onStreamFinished: root.glassOnReply(text) }
        onExited: (exitCode, exitStatus) => { if (root.gDirty) { root.gDirty = false; Qt.callLater(root.glassApplyNow) } }
    }
    function glassApplyNow() {
        if (glassApplyProc.running) { root.gDirty = true; return }
        glassApplyProc.command = ["python3", root.glassCtl, "apply", JSON.stringify(root.glassCurrent())]
        glassApplyProc.running = true
    }
    function glassOnReply(raw) {
        let j = null
        try { j = JSON.parse(raw.trim()) } catch (e) { return }
        root.gStatus = j.error ? j.error : (j.message || "")
    }

    Process {
        id: glassStateProc
        stdout: StdioCollector { onStreamFinished: root.glassOnState(text) }
    }
    function glassRefresh() {
        if (glassStateProc.running) return
        glassStateProc.command = ["python3", root.glassCtl, "state"]
        glassStateProc.running = true
    }
    function glassOnState(raw) {
        let j = null
        try { j = JSON.parse(raw.trim()) } catch (e) { root.gStatus = Translation.tr("Could not read the HyprGlass state"); return }
        if (j.error) { root.gStatus = j.error; return }
        root.gPlugin = j.plugin === true
        root.gAuto = j.auto === true
        const previousWallpaper = root.gWallpaper
        root.gWallpaper = String(j.wallpaper || "")
        root.gPvImages = j.images || []
        if (previousWallpaper !== root.gWallpaper) {
            root.gPvIdx = root.gPvImages.indexOf(root.gWallpaper)
            root.glassLoadPalette()
        }
        let list = []
        Object.keys(j.builtins || {}).forEach(n => list.push({ name: n, custom: false, s: j.builtins[n] }))
        Object.keys(j.custom || {}).forEach(n => list.push({ name: n, custom: true, s: j.custom[n] }))
        root.gPresets = list
        const idle = !root.gDragging && !glassApplyTimer.running && !glassApplyProc.running
        if (!root.gLoaded || idle) root.glassUse(j.settings)
        root.gLoaded = true
    }

    Process {
        id: glassPaletteProc
        stdout: StdioCollector { onStreamFinished: { try { root.gPalette = JSON.parse(text.trim()).colors || [] } catch (e) {} } }
    }
    function glassLoadPalette() {
        if (glassPaletteProc.running) return
        glassPaletteProc.command = ["python3", root.glassCtl, "palette"]
        glassPaletteProc.running = true
    }

    Process {
        id: glassLoadProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    root.gPlugin = j.plugin === true
                    root.gStatus = j.error ? j.error : (j.plugin ? Translation.tr("HyprGlass loaded") : Translation.tr("Could not load HyprGlass: ") + (j.message || ""))
                } catch (e) {}
            }
        }
    }
    function glassLoadPlugin() {
        root.gStatus = Translation.tr("Loading HyprGlass...")
        glassLoadProc.command = ["python3", root.glassCtl, "load"]
        glassLoadProc.running = true
    }

    Process {
        id: glassWallProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    if (j.rgb) { root.glassSetRgb(j.rgb); root.glassQueueApply() }
                    root.gStatus = j.message || ""
                } catch (e) {}
            }
        }
    }
    function glassMatchWallpaper() {
        glassWallProc.command = ["python3", root.glassCtl, "wall"]
        glassWallProc.running = true
    }

    Process {
        id: glassAutoProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    if (j.settings) root.glassUse(j.settings)
                    root.gStatus = j.error ? j.error : (j.message || "")
                } catch (e) {}
            }
        }
    }
    function glassSetAuto(on) {
        root.gAuto = on
        GlobalStates.hyprglassAuto = on
        glassAutoProc.command = ["python3", root.glassCtl, "auto", on ? "on" : "off"]
        glassAutoProc.running = true
    }

    Process {
        id: glassPresetProc
        onExited: (exitCode, exitStatus) => root.glassRefresh()
    }
    function glassSavePreset(name) {
        let n = String(name).trim()
        if (n.length === 0) {
            let k = root.gPresets.filter(p => p.custom).length + 1
            while (root.gPresets.some(p => p.name === "Look " + k)) k++
            n = "Look " + k
        }
        glassPresetProc.command = ["python3", root.glassCtl, "preset-save", n, JSON.stringify(Object.assign({}, root.glassCurrent(), { dynamic: root.gAuto }))]
        glassPresetProc.running = true
        root.gStatus = Translation.tr("Saved preset: ") + n
    }
    function glassDeletePreset(name) {
        glassPresetProc.command = ["python3", root.glassCtl, "preset-delete", String(name)]
        glassPresetProc.running = true
    }
    property bool gBusy: false
    property int gPvIdx: -1
    property var gPvImages: []

    Process {
        id: glassEnableProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    if (j.plugin !== undefined) root.gPlugin = j.plugin === true
                    root.gStatus = j.error ? j.error : (j.message || "")
                } catch (e) {}
                root.glassRefresh()
            }
        }
        onExited: (exitCode, exitStatus) => { root.gBusy = false }
    }
    function glassSetEnabled(on) {
        if (root.gBusy) return
        root.gBusy = true
        root.gStatus = on ? Translation.tr("Turning HyprGlass on...") : Translation.tr("Turning HyprGlass off...")
        glassEnableProc.command = ["python3", root.glassCtl, "enable", on ? "on" : "off"]
        glassEnableProc.running = true
    }
    function glassPvPath() {
        return root.gPvIdx >= 0 && root.gPvIdx < root.gPvImages.length
            ? root.gPvImages[root.gPvIdx]
            : root.gWallpaper
    }

    function glassStepPreview(direction) {
        const count = root.gPvImages.length
        if (count === 0) return

        let index = root.gPvIdx
        if (index < 0 || index >= count)
            index = direction > 0 ? -1 : 0

        root.gPvIdx = (index + direction + count) % count
    }
    Process {
        id: glassUseProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    if (j.settings) root.glassUse(j.settings)
                    root.gAuto = j.auto === true
                    GlobalStates.hyprglassAuto = j.auto === true
                    root.gStatus = j.error ? j.error : (j.message || "")
                } catch (e) {}
            }
        }
    }
    function glassUsePreset(s) {
        if (glassUseProc.running) return
        glassUseProc.command = ["python3", root.glassCtl, "use", JSON.stringify(s)]
        glassUseProc.running = true
    }
    function ensureGlassState() { root.glassRefresh(); root.glassLoadPalette() }

    // ---------------- SDDM themes tab ----------------
    property bool sddmScanning: false
    property bool sddmScanned: false

    function fileUrlOf(p) {
        if (!p) return ""
        return "file://" + String(p).split("/").map(encodeURIComponent).join("/")
    }

    Process {
        id: sddmScanProc
        stdout: StdioCollector {
            onStreamFinished: root.loadSddmThemes(text)
        }
        onExited: (exitCode, exitStatus) => { root.sddmScanning = false }
    }

    function scanSddmThemes() {
        if (root.sddmScanning) return
        root.sddmScanning = true
        sddmScanProc.command = ["bash", "-c", "$HOME/.config/quickshell/ii/scripts/sddm-scan.sh"]
        sddmScanProc.running = true
    }

    function ensureSddmScan() {
        if (root.sddmScanned || root.sddmScanning) return
        sddmCacheProc.command = ["bash", "-c", "cat \"$HOME/.cache/quickshell/sddm-scan.json\" 2>/dev/null"]
        sddmCacheProc.running = true
        root.scanSddmThemes()
    }

    Process {
        id: sddmCacheProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.sddmScanned && text.trim().length > 0) root.mergeSddmThemes(text, false)
            }
        }
    }

    function sddmRowFor(t) {
        return {
            themeName: String(t.name),
            themePath: String(t.path),
            previewUrl: root.fileUrlOf(t.preview),
            animType: String(t.animType || ""),
            animPath: String(t.anim || ""),
            stageA: String(t.stageA || ""),
            stageB: String(t.stageB || ""),
            isActive: t.isActive === true,
            capture1: String(t.capture1 || ""),
            capture2: String(t.capture2 || ""),
            captureTried: t.captureTried === true,
            clip: String(t.clip || ""),
            dark: t.dark === true,
            previewSrc: String(t.previewSrc || ""),
            previewWhy: String(t.previewWhy || "")
        }
    }

    // Merge into the live model: update in place, drop vanished themes, insert new ones. Never clear(),
    // so the scroll position and an open pop-out survive a refresh.
    function mergeSddmThemes(raw, fromScan) {
        let themes = []
        try { themes = JSON.parse(raw.trim() || "[]") } catch (e) { console.log("[WallpaperPicker] SDDM scan parse error:", e); return }
        const rows = themes.map(t => root.sddmRowFor(t))
        const wanted = {}
        rows.forEach(r => { wanted[r.themeName] = true })
        for (let i = sddmModel.count - 1; i >= 0; i--) {
            if (!wanted[sddmModel.get(i).themeName]) sddmModel.remove(i)
        }
        rows.forEach((r, pos) => {
            let found = -1
            for (let i = 0; i < sddmModel.count; i++) {
                if (sddmModel.get(i).themeName === r.themeName) { found = i; break }
            }
            if (found < 0) sddmModel.insert(Math.min(pos, sddmModel.count), r)
            else sddmModel.set(found, r)
        })
        let an = "", ap = ""
        themes.forEach(t => { if (t.isActive === true) { an = String(t.name); ap = String(t.path) } })
        root.sddmActiveName = an
        root.sddmActivePath = ap
        root.sddmMissingCount = root.sddmMissingPairs().length / 2
        if (fromScan) root.sddmScanned = true
        Qt.callLater(root.applySddmResume)
    }

    function loadSddmThemes(raw) { root.mergeSddmThemes(raw, true) }

    // After Test / capture the panel is reopened by an IPC call; put the user back where they were.
    function applySddmResume() {
        const r = GlobalStates.wallpaperPickerResume
        if (!r || r.tab !== 2 || sddmModel.count === 0) return
        GlobalStates.wallpaperPickerResume = null
        sddmGrid.scrollTargetY = r.scrollY || 0
        sddmGrid.contentY = r.scrollY || 0
        if (r.detailName) {
            for (let i = 0; i < sddmModel.count; i++) {
                if (sddmModel.get(i).themeName === r.detailName) { root.openSddmDetail(i); break }
            }
        }
    }

    // ---------------- SDDM: detail screen, test and apply ----------------
    function sddmPagesFor(t) {
        let pages = []
        if (!t) return pages
        if (t.animType === "video" && t.animPath && root.sddmVideoSupported)
            pages.push({ kind: "video", url: root.fileUrlOf(t.animPath), poster: String(t.previewUrl || ""), label: "Animation" })
        else if (t.animType === "gif" && t.animPath)
            pages.push({ kind: "gif", url: root.fileUrlOf(t.animPath), label: "Animation" })
        if (t.clip && !t.animPath) pages.push({ kind: "video", url: root.fileUrlOf(t.clip), poster: String(t.previewUrl || ""), label: "Animation (recorded)" })
        if (t.stageA) pages.push({ kind: "image", url: root.fileUrlOf(t.stageA), label: "Stage 1" })
        if (t.stageB) pages.push({ kind: "image", url: root.fileUrlOf(t.stageB), label: "Stage 2" })
        if (t.capture1) pages.push({ kind: "image", url: root.fileUrlOf(t.capture1), label: "Login screen" })
        if (t.capture2) pages.push({ kind: "image", url: root.fileUrlOf(t.capture2), label: "After a key press" })
        if (pages.length === 0 && t.previewUrl) pages.push({ kind: "image", url: String(t.previewUrl), label: "Preview" })
        return pages
    }

    function openSddmDetail(idx) {
        if (idx < 0 || idx >= sddmModel.count) return
        const t = sddmModel.get(idx)
        root.sddmDetail = {
            themeName: String(t.themeName), themePath: String(t.themePath), previewUrl: String(t.previewUrl),
            animType: String(t.animType), animPath: String(t.animPath),
            stageA: String(t.stageA), stageB: String(t.stageB), isActive: t.isActive === true,
            capture1: String(t.capture1), capture2: String(t.capture2),
            clip: String(t.clip)
        }
        sddmPageList.currentIndex = 0
    }

    function closeSddmDetail() { root.sddmDetail = null }

    property int sddmMissingCount: 0

    // name/path pairs of themes that still have no usable thumbnail (none or black) and no capture yet
    function sddmMissingPairs() {
        let out = []
        for (let i = 0; i < sddmModel.count; i++) {
            const m = sddmModel.get(i)
            if ((m.previewUrl === "" || m.dark === true) && m.capture1 === "" && m.captureTried !== true) out.push(String(m.themeName), String(m.themePath))
        }
        return out
    }

    // Saves where the user is, hides the panel, runs the capture script (it reopens the panel when done).
    function startSddmCapture(pairs) {
        if (!pairs || pairs.length < 2) return
        GlobalStates.wallpaperPickerResume = { tab: 2, scrollY: sddmGrid.contentY, detailName: root.sddmDetail ? String(root.sddmDetail.themeName) : "" }
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/sddm-capture.sh"].concat(pairs))
        GlobalStates.wallpaperPickerOpen = false
    }

    function testSddmTheme(path) {
        if (!path) return
        GlobalStates.wallpaperPickerResume = { tab: 2, scrollY: sddmGrid.contentY, detailName: root.sddmDetail ? String(root.sddmDetail.themeName) : "" }
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/sddm-test.sh", path])
        GlobalStates.wallpaperPickerOpen = false   // get the panel out of the way; sddm-test.sh reopens it when the test window closes
    }

    Process {
        id: sddmApplyProc
        property string themeName: ""
        onExited: (exitCode, exitStatus) => {
            root.sddmBusy = ""
            if (exitCode === 0) {
                Quickshell.execDetached(["notify-send", "SDDM", "Login theme set to " + sddmApplyProc.themeName + " (shown at the next login screen)", "-a", "Shell"])
                root.closeSddmDetail()
                root.scanSddmThemes()
            } else {
                Quickshell.execDetached(["notify-send", "-u", "critical", "SDDM", "Could not set " + sddmApplyProc.themeName + " (cancelled or failed, exit " + exitCode + " - see /tmp/sddm-picker-apply.log)", "-a", "Shell"])
            }
        }
    }

    function applySddmTheme() {
        const t = root.sddmDetail
        if (!t) return
        // runs detached: the password dialog takes focus and closes this panel, and a child of the panel would die with it
        GlobalStates.wallpaperPickerResume = { tab: 2, scrollY: sddmGrid.contentY, detailName: String(t.themeName) }
        Quickshell.execDetached(["bash", "-c", 'echo "$(date) apply start: $2 $3" > /tmp/sddm-picker-apply.log; pkexec /usr/bin/bash "$1" "$2" "$3" >> /tmp/sddm-picker-apply.log 2>&1; rc=$?; echo "exit=$rc" >> /tmp/sddm-picker-apply.log; if [ $rc -eq 0 ]; then notify-send -a Shell SDDM "Login theme set to $2"; else notify-send -u critical -a Shell SDDM "Could not set $2 (exit $rc, see /tmp/sddm-picker-apply.log)"; fi; if [ $rc -eq 0 ]; then bash "$HOME/.config/quickshell/ii/scripts/sddm-scan.sh" >/dev/null 2>&1; fi; qs -c ii ipc call wallpaperPicker open >/dev/null 2>&1; exit $rc', "sddm-apply", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/sddm-apply.sh", String(t.themeName), String(t.themePath)])
        GlobalStates.wallpaperPickerOpen = false
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
    property var previewTags: []
    property var selectedPreviewTags: []
    property bool previewTagsLoading: false
    onPreviewItemChanged: root.fetchPreviewTags(previewItem)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        enabled: root.stateLoaded

        RowLayout {
            spacing: 8
            RippleButton { buttonText: Translation.tr("Library"); toggled: root.currentTab === 0; onClicked: root.currentTab = 0 }
            RippleButton { buttonText: Translation.tr("Search"); toggled: root.currentTab === 1; onClicked: { root.currentTab = 1; root.ensureInitialBrowse() } }
            RippleButton { buttonText: Translation.tr("SDDM"); toggled: root.currentTab === 2; onClicked: { root.currentTab = 2; root.ensureSddmScan() } }
            RippleButton { buttonText: Translation.tr("Glass"); toggled: root.currentTab === 3; onClicked: { root.currentTab = 3; root.ensureGlassState() } }
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
                    ? Translation.tr("All sources")
                    : root.providerDescription(root.searchProvider)
            }
            Item { Layout.fillWidth: true }
            StyledText { id: statusText; visible: root.currentTab !== 2 && root.currentTab !== 3; color: Appearance.colors.colOnLayer1 }
        }

        StackLayout {
            currentIndex: root.currentTab
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 160
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.small

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 0

                            StyledText {
                                Layout.margins: 8
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                text: Translation.tr("Quick access")
                            }

                            Repeater {
                                model: [
                                    { icon: "home", name: "Home", path: Directories.home },
                                    { icon: "docs", name: "Documents", path: Directories.documents },
                                    { icon: "download", name: "Downloads", path: Directories.downloads },
                                    { icon: "image", name: "Pictures", path: Directories.pictures },
                                    { icon: "movie", name: "Videos", path: Directories.videos },
                                    { icon: "wallpaper", name: "Wallpapers", path: root.wallpaperDir }
                                ]
                                delegate: RippleButton {
                                    id: quickDirButton
                                    required property var modelData
                                    Layout.fillWidth: true
                                    onClicked: Wallpapers.setDirectory(quickDirButton.modelData.path)
                                    toggled: FileUtils.trimFileProtocol(Wallpapers.effectiveDirectory).replace(/\/+$/, "") === quickDirButton.modelData.path.replace(/\/+$/, "")
                                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                    buttonRadius: Appearance.rounding.small
                                    implicitHeight: 36
                                    contentItem: RowLayout {
                                        MaterialSymbol {
                                            color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                            iconSize: Appearance.font.pixelSize.larger
                                            text: quickDirButton.modelData.icon
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            color: quickDirButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                            text: quickDirButton.modelData.name
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            AddressBar {
                                Layout.fillWidth: true
                                directory: Wallpapers.effectiveDirectory
                                onNavigateToDirectory: path => Wallpapers.setDirectory(path.length === 0 ? "/" : path)
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
                                property real scrollTargetY: 0
                                Behavior on contentY {
                                    NumberAnimation { id: libraryScrollAnim; duration: 140; easing.type: Easing.OutCubic }
                                }
                                onContentYChanged: { if (!libraryScrollAnim.running) scrollTargetY = contentY }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.NoButton
                                    onWheel: (wheel) => {
                                        const delta = wheel.angleDelta.y / 120
                                        const factor = Math.abs(wheel.angleDelta.y) >= 120 ? root.wheelMouseStep : root.wheelTouchpadStep  // mouse notch : touchpad
                                        const maxY = Math.max(0, libraryGrid.contentHeight - libraryGrid.height)
                                        const base = libraryScrollAnim.running ? libraryGrid.scrollTargetY : libraryGrid.contentY
                                        const targetY = Math.max(0, Math.min(base - delta * factor, maxY))
                                        libraryGrid.scrollTargetY = targetY
                                        libraryGrid.contentY = targetY
                                        wheel.accepted = true
                                    }
                                }
                                property string selectedPath: ""
                                anchors.fill: parent
                                clip: true
                                cellWidth: 220
                                cellHeight: 140
                                model: Wallpapers.folderModel
                                delegate: Item {
                                    id: libItem
                                    width: libraryGrid.cellWidth
                                    height: libraryGrid.cellHeight
                                    required property string fileName
                                    required property string filePath
                                    required property bool fileIsDir
                                    property bool showMenu: false
                                    Rectangle {
                                        id: libItemBg
                                        readonly property bool selected: libItem.fileIsDir && libraryGrid.selectedPath === libItem.filePath
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        radius: Appearance.rounding.small
                                        color: selected ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2
                                        border.width: selected ? 2 : 0
                                        border.color: Appearance.m3colors.m3primary.hslLightness > 0.5 ? "black" : "white"
                                        Behavior on color {
                                            ColorAnimation { duration: 150 }
                                        }
                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            visible: libItem.fileIsDir
                                            spacing: 4
                                            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; iconSize: 40; text: "folder"; color: Appearance.m3colors.m3onSurface }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.maximumWidth: libraryGrid.cellWidth - 24
                                                elide: Text.ElideMiddle
                                                color: Appearance.colors.colOnLayer2
                                                text: libItem.fileName
                                            }
                                        }
                                        Image {
                                            anchors.fill: parent
                                            visible: !libItem.fileIsDir
                                            source: `file://${libItem.filePath}`
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (libItem.fileIsDir) libraryGrid.selectedPath = libItem.filePath
                                                else root.selectLibraryImage(libItem.filePath)
                                            }
                                            onDoubleClicked: {
                                                if (libItem.fileIsDir) Wallpapers.setDirectory(libItem.filePath)
                                            }
                                        }
                                        RippleButton {
                                            visible: !libItem.fileIsDir
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
                                        visible: libItem.showMenu && !libItem.fileIsDir
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
                                                onClicked: { libItem.showMenu = false; root.previewItem = libItem.filePath }
                                            }
                                            MenuButton {
                                                Layout.fillWidth: true
                                                buttonText: Translation.tr("Delete")
                                                onClicked: { libItem.showMenu = false; root.deleteLibraryImage(libItem.filePath) }
                                            }
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
                            model: ["wallhaven", "unsplash", "pexels"]
                            currentIndex: Math.max(0, model.indexOf(root.searchProvider))
                            onCurrentTextChanged: { root.searchProvider = currentText; root.scheduleSave() }
                        }
                        ComboBox {
                            id: modeCombo
                            model: ["Single provider", "All sources"]
                            readonly property var modeValues: ["single", "all"]
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
                            placeholderText: Translation.tr("Search tags...")
                            onAccepted: { searchDebounce.stop(); root.performSearchDispatch() }
                            onTextChanged: { root.scheduleSave(); if (text.length === 0) { searchDebounce.stop(); return }; if (root.wallhavenActive && root.wallhavenMode !== "search") root.wallhavenMode = "search"; searchDebounce.restart() }
                        }
                        Timer { id: searchDebounce; interval: 500; repeat: false; onTriggered: root.performSearchDispatch() }
                        RippleButton { buttonText: Translation.tr("Search"); onClicked: root.performSearchDispatch() }
                        RippleButton { buttonText: Translation.tr("🎲 Surprise me"); onClicked: root.surpriseMe() }
                    }

                    RowLayout {
                        spacing: 6
                        visible: root.wallhavenActive
                        Repeater {
                            model: [
                                { key: "search", label: "Search" },
                                { key: "latest", label: "Latest" },
                                { key: "toplist", label: "Toplist" },
                                { key: "favorites", label: "Most favorited" },
                                { key: "views", label: "Most viewed" },
                                { key: "random", label: "Random" }
                            ]
                            delegate: RippleButton {
                                required property var modelData
                                buttonText: Translation.tr(modelData.label)
                                toggled: root.wallhavenMode === modelData.key
                                onClicked: root.setWallhavenMode(modelData.key)
                            }
                        }
                        ComboBox {
                            visible: root.wallhavenMode === "toplist"
                            model: ["Last day", "Last 3 days", "Last week", "Last month", "Last 3 months", "Last 6 months", "Last year"]
                            readonly property var rangeValues: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]
                            currentIndex: rangeValues.indexOf(root.wallhavenTopRange)
                            onActivated: (index) => { root.wallhavenTopRange = rangeValues[index]; root.performSearchDispatch() }
                        }
                        ComboBox {
                            visible: root.wallhavenMode === "search"
                            model: ["Best match", "Most favorited", "Most viewed", "Newest"]
                            readonly property var sortValues: ["relevance", "favorites", "views", "date_added"]
                            currentIndex: sortValues.indexOf(root.wallhavenSort)
                            onActivated: (index) => { root.wallhavenSort = sortValues[index]; root.performSearchDispatch() }
                        }
                        StyledText { font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2; text: Translation.tr("Category:") }
                        ComboBox {
                            model: ["General", "Anime", "General + Anime"]
                            readonly property var catValues: ["general", "anime", "both"]
                            currentIndex: catValues.indexOf(root.wallhavenCategory)
                            onActivated: (index) => { root.wallhavenCategory = catValues[index]; root.performSearchDispatch() }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 4
                        visible: root.wallhavenActive
                        Rectangle {
                            implicitWidth: 70
                            implicitHeight: 22
                            radius: 4
                            color: Appearance.colors.colLayer2
                            border.width: root.selectedColor === "" ? 2 : 0
                            border.color: Appearance.m3colors.m3onSurface
                            StyledText {
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                text: Translation.tr("All colors")
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.selectedColor = ""; root.performSearchDispatch() }
                            }
                        }
                        Repeater {
                            model: root.wallhavenColors
                            delegate: Rectangle {
                                required property string modelData
                                implicitWidth: 22
                                implicitHeight: 22
                                radius: 4
                                color: `#${modelData}`
                                border.width: root.selectedColor === modelData ? 2 : 0
                                border.color: Appearance.m3colors.m3onSurface
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedColor = (root.selectedColor === parent.modelData) ? "" : parent.modelData
                                        root.performSearchDispatch()
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 10
                        StyledText { font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2; text: Translation.tr("Min height (px):") }
                        SpinBox {
                            from: 0; to: 8000; stepSize: 120
                            value: root.minHeightPx
                            onValueChanged: { root.minHeightPx = value; root.scheduleSave() }
                        }
                        CheckBox {
                            visible: root.wallhavenActive
                            text: Translation.tr("Only images at least screen size")
                            checked: root.wallhavenMatchScreen
                            onClicked: { root.wallhavenMatchScreen = checked; root.performSearchDispatch() }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ListModel {
                        id: resultsListModel
                        dynamicRoles: true
                    }
                    GridView {
                        id: resultsGrid
                        property real scrollTargetY: 0
                        Behavior on contentY {
                            NumberAnimation { id: resultsScrollAnim; duration: 140; easing.type: Easing.OutCubic }
                        }
                        onContentYChanged: { if (!resultsScrollAnim.running) scrollTargetY = contentY }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: (wheel) => {
                                const delta = wheel.angleDelta.y / 120
                                const factor = Math.abs(wheel.angleDelta.y) >= 120 ? root.wheelMouseStep : root.wheelTouchpadStep  // mouse notch : touchpad
                                const maxY = Math.max(0, resultsGrid.contentHeight - resultsGrid.height)
                                const base = resultsScrollAnim.running ? resultsGrid.scrollTargetY : resultsGrid.contentY
                                const targetY = Math.max(0, Math.min(base - delta * factor, maxY))
                                resultsGrid.scrollTargetY = targetY
                                resultsGrid.contentY = targetY
                                wheel.accepted = true
                            }
                        }
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
                                Item { Layout.fillHeight: true }
                                BooruImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    property var modelData: parent.parent.payload
                                    imageData: parent.parent.payload
                                    rowHeight: Math.min(parent.parent.height - 34, (parent.parent.width - 12) / Math.max(0.1, parent.parent.payload.aspect_ratio))
                                    manualDownload: true
                                    previewDownloadPath: root.previewCacheDir
                                    downloadPath: root.wallpaperDir
                                    nsfwPath: root.wallpaperDir
                                    downloadTrackingUrl: parent.parent.payload.__downloadLocation ?? ""
                                    onClicked: root.previewItem = parent.parent.payload
                                }
                                Item { Layout.fillHeight: true }
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
            // ---- SDDM themes tab ----
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                            text: root.sddmScanning ? Translation.tr("Scanning for SDDM themes...") : (Translation.tr("%1 SDDM theme(s) found").arg(sddmModel.count) + (root.sddmActiveName.length > 0 ? "   |   " + Translation.tr("current: %1").arg(root.sddmActiveName) : ""))
                        }
                        RippleButton {
                            visible: root.sddmActivePath.length > 0
                            buttonText: Translation.tr("Test current")
                            onClicked: root.testSddmTheme(root.sddmActivePath)
                        }
                        RippleButton {
                            visible: root.sddmMissingCount > 0 && !root.sddmScanning
                            buttonText: Translation.tr("Capture login screens (%1)").arg(root.sddmMissingCount)
                            onClicked: root.startSddmCapture(root.sddmMissingPairs())
                        }
                        RippleButton {
                            buttonText: Translation.tr("Rescan")
                            onClicked: root.scanSddmThemes()
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListModel { id: sddmModel }

                        GridView {
                            id: sddmGrid
                            property real scrollTargetY: 0
                            Behavior on contentY {
                                NumberAnimation { id: sddmScrollAnim; duration: 140; easing.type: Easing.OutCubic }
                            }
                            onContentYChanged: { if (!sddmScrollAnim.running) scrollTargetY = contentY }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: (wheel) => {
                                    const delta = wheel.angleDelta.y / 120
                                    const factor = Math.abs(wheel.angleDelta.y) >= 120 ? root.wheelMouseStep : root.wheelTouchpadStep
                                    const maxY = Math.max(0, sddmGrid.contentHeight - sddmGrid.height)
                                    const base = sddmScrollAnim.running ? sddmGrid.scrollTargetY : sddmGrid.contentY
                                    const targetY = Math.max(0, Math.min(base - delta * factor, maxY))
                                    sddmGrid.scrollTargetY = targetY
                                    sddmGrid.contentY = targetY
                                    wheel.accepted = true
                                }
                            }
                            anchors.fill: parent
                            clip: true
                            cellWidth: 260
                            cellHeight: 190
                            model: sddmModel
                            delegate: Item {
                                id: sddmItem
                                width: sddmGrid.cellWidth
                                height: sddmGrid.cellHeight
                                required property string themeName
                                required property string previewUrl
                                required property string animType
                                required property bool isActive
                                required property int index
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer2
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        anchors.bottomMargin: 30
                                        visible: sddmItem.previewUrl.length > 0
                                        source: sddmItem.previewUrl
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -15
                                        visible: sddmItem.previewUrl.length === 0
                                        iconSize: 40
                                        color: Appearance.m3colors.m3onSurface
                                        text: "image"
                                    }
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 30
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.15)
                                        StyledText {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                            color: Appearance.m3colors.m3onSurface
                                            text: sddmItem.themeName
                                        }
                                    }
                                    Rectangle {
                                        visible: sddmItem.animType.length > 0
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: 8
                                        height: 22
                                        width: animLabel.implicitWidth + 16
                                        radius: height / 2
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.2)
                                        border.width: 1
                                        border.color: Appearance.colors.colPrimary
                                        StyledText {
                                            id: animLabel
                                            anchors.centerIn: parent
                                            color: Appearance.colors.colPrimary
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.bold: true
                                            text: sddmItem.animType === "video" ? Translation.tr("VIDEO") : (sddmItem.animType === "gif" ? Translation.tr("GIF") : Translation.tr("ANIMATED"))
                                        }
                                    }
                                    Rectangle {
                                        visible: sddmItem.isActive
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        height: 22
                                        width: activeLabel.implicitWidth + 16
                                        radius: height / 2
                                        color: Appearance.colors.colPrimary
                                        StyledText {
                                            id: activeLabel
                                            anchors.centerIn: parent
                                            color: Appearance.colors.colOnPrimary
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.bold: true
                                            text: Translation.tr("ACTIVE")
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openSddmDetail(sddmItem.index)
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.sddmScanned && !root.sddmScanning && sddmModel.count === 0
                            color: Appearance.colors.colOnLayer2
                            text: Translation.tr("No SDDM themes found")
                        }
                    }
                }
            }
            Item {
                id: glassTab

                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    ColumnLayout {
                        Layout.preferredWidth: 440
                        Layout.maximumWidth: 440
                        Layout.alignment: Qt.AlignTop
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: Appearance.rounding.small
                            color: root.gPlugin ? Appearance.colors.colLayer2 : Appearance.colors.colSecondaryContainer
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 6
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: root.gPlugin ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer
                                    text: root.gPlugin ? Translation.tr("HyprGlass is on: foot and kitty update as you adjust") : Translation.tr("HyprGlass is off")
                                }
                                RippleButton {
                                    enabled: !root.gBusy
                                    buttonText: root.gPlugin ? Translation.tr("Turn off") : Translation.tr("Turn on")
                                    toggled: root.gPlugin
                                    onClicked: root.glassSetEnabled(!root.gPlugin)
                                }
                            }
                        }

                        StyledText { text: Translation.tr("Tint colour"); font.bold: true; color: Appearance.colors.colOnLayer2 }
                        RowLayout {
                            spacing: 12
                            Rectangle {
                                id: glSv
                                Layout.preferredWidth: 230
                                Layout.preferredHeight: 150
                                radius: 10
                                color: Qt.hsva(root.gHue, 1, 1, 1)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1) }
                                    }
                                }
                                Rectangle {
                                    width: 16; height: 16; radius: 8
                                    color: root.gRgb
                                    border.width: 2
                                    border.color: "white"
                                    x: root.gSat * glSv.width - 8
                                    y: (1 - root.gVal) * glSv.height - 8
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    function pick(m) {
                                        root.glassSetHsv(root.gHue, Math.max(0, Math.min(1, m.x / width)), 1 - Math.max(0, Math.min(1, m.y / height)))
                                    }
                                    onPressed: (m) => { root.gDragging = true; pick(m) }
                                    onPositionChanged: (m) => { if (pressed) pick(m) }
                                    onReleased: root.gDragging = false
                                    onCanceled: root.gDragging = false
                                }
                            }
                            Rectangle {
                                id: glHue
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 150
                                radius: 8
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#FF0000" }
                                    GradientStop { position: 0.1667; color: "#FFFF00" }
                                    GradientStop { position: 0.3333; color: "#00FF00" }
                                    GradientStop { position: 0.5; color: "#00FFFF" }
                                    GradientStop { position: 0.6667; color: "#0000FF" }
                                    GradientStop { position: 0.8333; color: "#FF00FF" }
                                    GradientStop { position: 1.0; color: "#FF0000" }
                                }
                                Rectangle {
                                    x: -2
                                    y: root.gHue * glHue.height - 3
                                    width: parent.width + 4; height: 6; radius: 3
                                    color: "transparent"
                                    border.width: 2
                                    border.color: "white"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    function pick(m) { root.glassSetHsv(Math.max(0, Math.min(1, m.y / height)), root.gSat, root.gVal) }
                                    onPressed: (m) => { root.gDragging = true; pick(m) }
                                    onPositionChanged: (m) => { if (pressed) pick(m) }
                                    onReleased: root.gDragging = false
                                    onCanceled: root.gDragging = false
                                }
                            }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignTop
                                spacing: 8
                                Rectangle {
                                    Layout.preferredWidth: 100
                                    Layout.preferredHeight: 32
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colSecondaryContainer
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: glHex.forceActiveFocus() }
                                    TextInput {
                                        id: glHex
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        maximumLength: 7
                                        selectByMouse: true
                                        color: Appearance.colors.colOnSecondaryContainer
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        Component.onCompleted: text = root.gRgb
                                        onEditingFinished: root.glassHexEntered(text)
                                        Connections {
                                            target: root
                                            function onGRgbChanged() { if (!glHex.activeFocus) glHex.text = root.gRgb }
                                        }
                                    }
                                }
                                StyledText { text: Translation.tr("From your wallpaper"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                                Flow {
                                    Layout.preferredWidth: 100
                                    spacing: 6
                                    Repeater {
                                        model: root.gPalette
                                        delegate: Rectangle {
                                            id: glSwatch
                                            required property var modelData
                                            width: 28; height: 28; radius: 14
                                            color: glSwatch.modelData
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.3)
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { root.glassSetRgb(glSwatch.modelData); root.glassQueueApply() }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText { text: Translation.tr("Glass"); font.bold: true; color: Appearance.colors.colOnLayer2 }
                        Repeater {
                            model: [
                                { prop: "gAlpha", label: "Tint strength", from: 0, to: 100, dec: 0, unit: "%" },
                                { prop: "gOpacity", label: "Glass opacity", from: 40, to: 100, dec: 0, unit: "%" },
                                { prop: "gBlur", label: "Blur", from: 0, to: 5, dec: 1, unit: "" },
                                { prop: "gBrightness", label: "Brightness", from: 50, to: 100, dec: 0, unit: "%" }
                            ]
                            delegate: RowLayout {
                                id: glRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                StyledText { Layout.preferredWidth: 100; color: Appearance.colors.colOnLayer2; text: Translation.tr(glRow.modelData.label) }
                                StyledSlider {
                                    Layout.fillWidth: true
                                    configuration: StyledSlider.Configuration.XS
                                    stopIndicatorValues: []
                                    usePercentTooltip: false
                                    from: glRow.modelData.from
                                    to: glRow.modelData.to
                                    value: root[glRow.modelData.prop]
                                    onMoved: { root[glRow.modelData.prop] = value; root.glassQueueApply() }
                                    onPressedChanged: root.gDragging = pressed
                                }
                                StyledText {
                                    Layout.preferredWidth: 52
                                    horizontalAlignment: Text.AlignRight
                                    color: Appearance.colors.colOnLayer2
                                    text: Number(root[glRow.modelData.prop]).toFixed(glRow.modelData.dec) + glRow.modelData.unit
                                }
                            }
                        }

                        RowLayout {
                            spacing: 8
                            RippleButton { buttonText: Translation.tr("Match wallpaper"); onClicked: root.glassMatchWallpaper() }
                            RippleButton { buttonText: root.gAuto ? Translation.tr("Auto: on") : Translation.tr("Auto: off"); toggled: root.gAuto; onClicked: root.glassSetAuto(!root.gAuto) }
                            RippleButton { buttonText: Translation.tr("Reset to favourite"); onClicked: root.glassReset() }
                        }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.bold: true
                                color: Appearance.colors.colOnLayer2
                                text: Translation.tr("Live preview") + (root.glassPvPath().length > 0 ? "   |   " + root.glassPvPath().split("/").pop() : "")
                            }

                            RippleButton {
                                buttonText: Translation.tr("Previous")
                                enabled: root.gPvImages.length > 0
                                onClicked: root.glassStepPreview(-1)
                            }
                            RippleButton {
                                buttonText: Translation.tr("Next")
                                enabled: root.gPvImages.length > 0
                                onClicked: root.glassStepPreview(1)
                            }
                        }
                        Item {
                            id: glPvMask
                            visible: false
                            width: glPv.width
                            height: glPv.height
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: 14 }
                        }
                        Item {
                            id: glPv
                            Layout.fillWidth: true
                            Layout.preferredHeight: 330
                            layer.enabled: true
                            layer.effect: MultiEffect { maskEnabled: true; maskSource: glPvMask }

                            Rectangle { anchors.fill: parent; color: "#101018" }
                            Image {
                                id: glPvImg
                                anchors.fill: parent
                                source: root.glassPvPath().length > 0 ? root.fileUrlOf(root.glassPvPath()) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Item {
                                id: glPane
                                x: glPv.width * 0.08
                                y: glPv.height * 0.14
                                width: glPv.width * 0.66
                                height: glPv.height * 0.68
                                property color tint: Qt.color(root.gRgb)
                                ShaderEffectSource {
                                    id: glPaneSrc
                                    anchors.fill: parent
                                    sourceItem: glPvImg
                                    sourceRect: Qt.rect(glPane.x, glPane.y, glPane.width, glPane.height)
                                    visible: false
                                }
                                Item {
                                    id: glPaneMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    Rectangle { anchors.fill: parent; radius: 12 }
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: glPaneSrc
                                    blurEnabled: true
                                    blurMax: 64
                                    autoPaddingEnabled: false
                                    blur: Math.min(1, root.gBlur / 5)
                                    brightness: (root.gBrightness - 100) / 80
                                    maskEnabled: true
                                    maskSource: glPaneMask
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: Qt.rgba(glPane.tint.r, glPane.tint.g, glPane.tint.b, (root.gAlpha / 100) * (root.gOpacity / 100))
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.18)
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 4
                                    StyledText { color: "white"; font.family: "monospace"; font.pixelSize: 13; textFormat: Text.RichText
                                        text: "<span style='color:#8bd5a0'>zakkaria@archlinux</span> <span style='color:#8aadf4'>~</span> ❯ ls --color" }
                                    StyledText { color: "white"; font.family: "monospace"; font.pixelSize: 13; textFormat: Text.RichText
                                        text: "<span style='color:#8aadf4'>Documents</span>  <span style='color:#8aadf4'>Downloads</span>  <span style='color:#f5a97f'>notes.md</span>  <span style='color:#a6da95'>build.sh</span>" }
                                    StyledText { color: "white"; font.family: "monospace"; font.pixelSize: 13; textFormat: Text.RichText
                                        text: "<span style='color:#8bd5a0'>zakkaria@archlinux</span> <span style='color:#8aadf4'>~</span> ❯ echo glass" }
                                    StyledText { color: "white"; font.family: "monospace"; font.pixelSize: 13; text: "glass" }
                                    Item { Layout.fillHeight: true }
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            opacity: 0.8
                            text: Translation.tr("The preview approximates the effect. Open foot and kitty windows show the real thing while HyprGlass is on.")
                        }

                        StyledText { text: Translation.tr("Presets"); font.bold: true; color: Appearance.colors.colOnLayer2 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: root.gPresets
                                delegate: Rectangle {
                                    id: glChip
                                    required property var modelData
                                    height: 32
                                    width: glChipRow.implicitWidth + 22
                                    radius: 16
                                    color: glChipMa.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                                    MouseArea {
                                        id: glChipMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.glassUsePreset(glChip.modelData.s)
                                    }
                                    RowLayout {
                                        id: glChipRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Rectangle { width: 14; height: 14; radius: 7; color: glChip.modelData.s.rgb; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
                                        MaterialSymbol {
                                            visible: glChip.modelData.s.dynamic === true
                                            iconSize: 16
                                            color: glChipMa.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            text: "auto_awesome"
                                        }
                                        StyledText {
                                            color: glChipMa.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            text: glChip.modelData.name
                                        }
                                        MaterialSymbol {
                                            visible: glChip.modelData.custom
                                            iconSize: 16
                                            color: glChipMa.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                            text: "close"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.glassDeletePreset(glChip.modelData.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            spacing: 8
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colSecondaryContainer
                                MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: glName.forceActiveFocus() }
                                TextInput {
                                    id: glName
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    maximumLength: 48
                                    selectByMouse: true
                                    color: Appearance.colors.colOnSecondaryContainer
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: { root.glassSavePreset(text); text = "" }
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    visible: glName.text.length === 0
                                    color: Appearance.colors.colOnSecondaryContainer
                                    opacity: 0.5
                                    text: Translation.tr("Name (optional). Saved with dynamic colours while Auto is on")
                                }
                            }
                            RippleButton { buttonText: Translation.tr("Save preset"); onClicked: { root.glassSavePreset(glName.text); glName.text = "" } }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            opacity: 0.8
                            text: root.gStatus
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ---- SDDM theme pop-out: preview / animation / stages, plus Test and Set ----
    Rectangle {
        id: sddmOverlay
        anchors.fill: parent
        visible: root.sddmDetail !== null
        color: "#ee000000"
        radius: Appearance.rounding.normal
        z: 1000

        readonly property var pages: root.sddmPagesFor(root.sddmDetail)

        onVisibleChanged: { if (visible) forceActiveFocus() }
        Keys.onEscapePressed: root.closeSddmDetail()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.closeSddmDetail()
            onWheel: (wheel) => { wheel.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                StyledText {
                    text: root.sddmDetail ? root.sddmDetail.themeName : ""
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: "white"
                }
                Repeater {
                    model: {
                        let b = []
                        const d = root.sddmDetail
                        if (d) {
                            if (d.isActive) b.push("ACTIVE")
                            if (d.animType === "video") b.push("VIDEO")
                            else if (d.animType === "gif") b.push("GIF")
                            else if (d.animType === "qml") b.push("ANIMATED")
                            if (d.stageA && d.stageB) b.push("2 STAGES")
                        }
                        return b
                    }
                    delegate: Rectangle {
                        required property string modelData
                        implicitHeight: 24
                        implicitWidth: badgeLabel.implicitWidth + 18
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colPrimary
                        StyledText {
                            id: badgeLabel
                            anchors.centerIn: parent
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            text: parent.modelData
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                RippleButton {
                    buttonText: Translation.tr("Close")
                    onClicked: root.closeSddmDetail()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: sddmPageList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: 250
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    interactive: count > 1
                    model: sddmOverlay.pages
                    delegate: Item {
                        id: pageItem
                        required property var modelData
                        required property int index
                        width: sddmPageList.width
                        height: sddmPageList.height
                        readonly property bool isCurrent: ListView.isCurrentItem

                        Image {
                            anchors.fill: parent
                            visible: pageItem.modelData.kind === "image"
                            source: pageItem.modelData.kind === "image" ? pageItem.modelData.url : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        AnimatedImage {
                            anchors.fill: parent
                            visible: pageItem.modelData.kind === "gif"
                            source: (pageItem.modelData.kind === "gif" && pageItem.isCurrent) ? pageItem.modelData.url : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            playing: visible
                        }
                        Image {
                            anchors.fill: parent
                            visible: pageItem.modelData.kind === "video" && videoPlayer.playbackState !== MediaPlayer.PlayingState
                            source: pageItem.modelData.kind === "video" ? (pageItem.modelData.poster || "") : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        VideoOutput {
                            id: videoOut
                            anchors.fill: parent
                            visible: pageItem.modelData.kind === "video" && videoPlayer.playbackState === MediaPlayer.PlayingState
                            fillMode: VideoOutput.PreserveAspectFit
                        }
                        MediaPlayer {
                            id: videoPlayer
                            source: (pageItem.modelData.kind === "video" && pageItem.isCurrent) ? pageItem.modelData.url : ""
                            videoOutput: videoOut
                            audioOutput: AudioOutput { muted: true }
                            loops: MediaPlayer.Infinite
                            onSourceChanged: { if (source.toString() !== "") play() }
                            Component.onCompleted: { if (source.toString() !== "") play() }
                        }
                    }
                }

                RippleButton {
                    visible: sddmPageList.count > 1 && sddmPageList.currentIndex > 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                    onClicked: sddmPageList.currentIndex = Math.max(0, sddmPageList.currentIndex - 1)
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 24; color: Appearance.m3colors.m3onSurface; text: "chevron_left" }
                }
                RippleButton {
                    visible: sddmPageList.count > 1 && sddmPageList.currentIndex < sddmPageList.count - 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize(Appearance.m3colors.m3surface, 0.3)
                    onClicked: sddmPageList.currentIndex = Math.min(sddmPageList.count - 1, sddmPageList.currentIndex + 1)
                    contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; iconSize: 24; color: Appearance.m3colors.m3onSurface; text: "chevron_right" }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        if (sddmPageList.count > 1) {
                            const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                            const dir = dy < 0 ? 1 : -1
                            sddmPageList.currentIndex = Math.max(0, Math.min(sddmPageList.count - 1, sddmPageList.currentIndex + dir))
                        }
                        wheel.accepted = true
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: sddmOverlay.pages.length > 0
                color: "white"
                text: {
                    const i = sddmPageList.currentIndex
                    const pg = sddmOverlay.pages[i]
                    if (!pg) return ""
                    return sddmOverlay.pages.length > 1 ? (pg.label + "   (" + (i + 1) + " / " + sddmOverlay.pages.length + ")") : pg.label
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: sddmOverlay.pages.length === 0
                color: "white"
                text: Translation.tr("No preview image was found for this theme. Use Test to see it live.")
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: !!(root.sddmDetail && root.sddmDetail.animType === "qml" && !root.sddmDetail.clip)
                color: "white"
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("This theme animates using QML, which can't be previewed here. Use Test to see it live.")
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.sddmBusy !== ""
                color: "white"
                text: root.sddmBusy
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                RippleButton {
                    buttonText: Translation.tr("Test")
                    onClicked: root.testSddmTheme(root.sddmDetail ? root.sddmDetail.themePath : "")
                }
                RippleButton {
                    enabled: root.sddmBusy === ""
                    buttonText: Translation.tr("Capture login screen")
                    onClicked: { if (root.sddmDetail) root.startSddmCapture([String(root.sddmDetail.themeName), String(root.sddmDetail.themePath)]) }
                }
                RippleButton {
                    enabled: root.sddmBusy === ""
                    buttonText: (root.sddmDetail && root.sddmDetail.isActive) ? Translation.tr("Re-apply as login theme") : Translation.tr("Set as login theme")
                    onClicked: root.applySddmTheme()
                }
            }
        }
    }
    Rectangle {
        id: previewOverlay
        anchors.fill: parent
        visible: root.previewItem !== null
        color: "#e8000000"
        z: 999

        readonly property bool isLocal: typeof root.previewItem === "string"
        readonly property bool isRemote: root.previewItem !== null && typeof root.previewItem === "object"
        readonly property string lowSource: isRemote ? ((root.wallhavenUseMidThumb && root.previewItem.__midUrl) ? root.previewItem.__midUrl : (root.previewItem.sample_url ?? root.previewItem.file_url ?? "")) : ""
        readonly property string highSource: isLocal ? ("file://" + root.previewItem) : (isRemote ? (root.previewItem.file_url ?? "") : "")

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true // swallow hover too, so thumbnails underneath don't show their tooltips
            onWheel: (wheel) => { wheel.accepted = true } // don't scroll the grid behind the preview
            onClicked: root.previewItem = null
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            ColumnLayout {
                visible: previewOverlay.isRemote
                Layout.preferredWidth: 240
                Layout.maximumWidth: 240
                Layout.fillHeight: true
                spacing: 10

                StyledText {
                    visible: root.previewTagsLoading || root.previewTags.length > 0
                    text: Translation.tr("Tags")
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: "white"
                }
                StyledText {
                    visible: root.previewTagsLoading
                    text: Translation.tr("Loading tags...")
                    color: "white"
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: tagFlow.childrenRect.height
                    Flow {
                        id: tagFlow
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: root.previewTags
                            delegate: Rectangle {
                                id: tagPill
                                required property string modelData
                                readonly property bool picked: root.selectedPreviewTags.indexOf(modelData) >= 0
                                radius: height / 2
                                color: picked ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                                border.width: picked ? 2 : 0
                                border.color: Appearance.colors.colPrimary
                                implicitHeight: 28
                                implicitWidth: tagLabel.implicitWidth + 24
                                StyledText {
                                    id: tagLabel
                                    anchors.centerIn: parent
                                    color: tagPill.picked ? Appearance.colors.colPrimary : Appearance.colors.colOnPrimary
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    text: (tagPill.picked ? "✓ " : "") + tagPill.modelData
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleTag(tagPill.modelData)
                                }
                            }
                        }
                    }
                }
                StyledText {
                    visible: !!(root.previewItem && root.previewItem.__attribution)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: "white"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.previewItem ? (root.previewItem.__attribution ?? "") : ""
                }
                RippleButton {
                    visible: root.previewTags.length > 0
                    enabled: root.selectedPreviewTags.length > 0
                    Layout.fillWidth: true
                    buttonText: root.selectedPreviewTags.length > 0
                        ? Translation.tr("Search %1 selected tag(s)").arg(root.selectedPreviewTags.length)
                        : Translation.tr("Select tags to search")
                    onClicked: root.searchSelectedTags()
                }
                RippleButton {
                    Layout.fillWidth: true
                    buttonText: Translation.tr("Download")
                    onClicked: root.downloadAndApplyRemote(root.previewItem, false)
                }
                RippleButton {
                    Layout.fillWidth: true
                    buttonText: Translation.tr("Set as wallpaper")
                    onClicked: { root.downloadAndApplyRemote(root.previewItem, true); root.previewItem = null }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The thumbnail is hidden the moment the full image is ready: the two have different
                // aspect ratios, which is what made the thumbnail poke out above and below the real image.
                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: previewHigh.status !== Image.Ready
                    source: previewOverlay.lowSource
                }
                Image {
                    id: previewHigh
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 1920
                    source: previewOverlay.highSource
                }
                StyledText {
                    visible: previewHigh.status === Image.Loading
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    color: "white"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Loading full resolution... %1%").arg(Math.round(previewHigh.progress * 100))
                }
            }
        }
    }
}
