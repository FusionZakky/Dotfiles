import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
            StyledText { id: statusText; color: Appearance.colors.colOnLayer1 }
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
                                        const factor = Math.abs(wheel.angleDelta.y) >= 120 ? 600 : 400  // mouse notch : touchpad
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
                                const factor = Math.abs(wheel.angleDelta.y) >= 120 ? 600 : 400  // mouse notch : touchpad
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
