-- Custom keybinds
-- Edit this file to change keybinds
-- Restart widgets after changes: CTRL+SUPER+R

--##! Edit this file
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), 
    { description = "Edit user keybinds" })

--##! Apps
hl.bind("SUPER + Return", hl.dsp.exec_cmd("foot"), 
    { description = "App: Terminal" })
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("vivaldi-stable"), 
    { description = "App: Browser" })
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("code"), 
    { description = "App: VSCode" })
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("obsidian"), 
    { description = "App: Obsidian" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("spotify"), 
    { description = "App: Spotify" })
hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd("slack"), 
    { description = "App: Slack" })
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("vivaldi-stable --new-tab https://claude.ai"), 
    { description = "App: Claude" })
hl.bind("SUPER + SHIFT + ALT + A", hl.dsp.exec_cmd("vivaldi-stable --new-tab https://copilot.microsoft.com"), 
    { description = "App: Copilot" })
hl.bind("SUPER + E", hl.dsp.exec_cmd("dolphin"), 
    { description = "App: File manager" })

--##! Window management
hl.bind("SUPER + Q", hl.dsp.window.close(), 
    { description = "Window: Close" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), 
    { description = "Window: Maximize (keep bar)" })
hl.bind("XF86FullScreen", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), 
    { description = "Window: Fullscreen (no bar)" })

-- Show desktop toggle
desktop_hidden = false
hidden_windows = {}
hidden_workspace_id = nil
desktop_toggle_busy = false

hl.bind("SUPER + D", function()
    if desktop_toggle_busy then return end
    desktop_toggle_busy = true

    if desktop_hidden then
        local current = hl.get_active_workspace()
        local target_ws = (current and current.id) or hidden_workspace_id
        for _, w in ipairs(hidden_windows) do
            pcall(function()
                hl.dispatch(hl.dsp.window.move({ workspace = target_ws, window = w, follow = false }))
            end)
        end
        hidden_windows = {}
        hidden_workspace_id = nil
        desktop_hidden = false
    else
        local current = hl.get_active_workspace()
        if current == nil then
            desktop_toggle_busy = false
            return
        end
        hidden_workspace_id = current.id
        local windows = hl.get_workspace_windows(current.id)
        hidden_windows = {}
        for _, w in ipairs(windows) do
            table.insert(hidden_windows, w)
            hl.dispatch(hl.dsp.window.move({ workspace = "special:hidden", window = w, follow = false }))
        end
        desktop_hidden = true
    end

    hl.timer(function()
        desktop_toggle_busy = false
    end, { timeout = 400, type = "oneshot" })
end, { description = "Window: Show desktop" })

hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), 
    { description = "Window: Float/Tile" })
hl.bind("SUPER + P", hl.dsp.window.pin(), 
    { description = "Window: Pin" })

--# Focus
hl.bind("SUPER + Left", hl.dsp.focus({ direction = "l" }), { description = "Window: Focus left" })
hl.bind("SUPER + Right", hl.dsp.focus({ direction = "r" }), { description = "Window: Focus right" })
hl.bind("SUPER + Up", hl.dsp.focus({ direction = "u" }), { description = "Window: Focus up" })
hl.bind("SUPER + Down", hl.dsp.focus({ direction = "d" }), { description = "Window: Focus down" })

--# Move
hl.bind("SUPER + SHIFT + Left", hl.dsp.window.move({ direction = "l" }), { description = "Window: Move left" })
hl.bind("SUPER + SHIFT + Right", hl.dsp.window.move({ direction = "r" }), { description = "Window: Move right" })
hl.bind("SUPER + SHIFT + Up", hl.dsp.window.move({ direction = "u" }), { description = "Window: Move up" })
hl.bind("SUPER + SHIFT + Down", hl.dsp.window.move({ direction = "d" }), { description = "Window: Move down" })

--# Split ratio
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true, description = "Window: Shrink split" })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true, description = "Window: Grow split" })

--##! Workspace
hl.bind("XF86LaunchA", hl.dsp.global("quickshell:overviewWorkspacesToggle"), 
    { description = "Workspace: Toggle overview" })
hl.bind("SUPER + Grave", hl.dsp.workspace.toggle_special("special"), 
    { description = "Workspace: Toggle scratchpad" })

--# Switch workspace
for i = 1, 9 do
    hl.bind("SUPER + " .. i, function()
        hl.dispatch(hl.dsp.focus({ workspace = i }))
    end, { description = "Workspace: Focus " .. i })
end

--# Move between workspaces
hl.bind("CTRL + SUPER + Left", hl.dsp.focus({ workspace = "r-1" }), 
    { description = "Workspace: Focus left" })
hl.bind("CTRL + SUPER + Right", hl.dsp.focus({ workspace = "r+1" }), 
    { description = "Workspace: Focus right" })

--##! Screenshot / Utilities
hl.bind("Print", hl.dsp.global("quickshell:regionScreenshot"), 
    { description = "Utilities: Screen snip" })
hl.bind("Print", hl.dsp.exec_cmd(
    "pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent"))
hl.bind("SUPER + Print", hl.dsp.global("quickshell:regionSearch"), 
    { description = "Utilities: Google Lens" })
hl.bind("SUPER + Print", hl.dsp.exec_cmd(
    "pidof slurp || ~/.config/hypr/hyprland/scripts/snip_to_search.sh"))

--##! Wallpaper
-- CTRL+SUPER+T moved to the custom wallpaper picker (see hyprland/keybinds.lua)
-- Stock wallpaper selector binds removed to avoid the conflict

--##! Session
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"), 
    { description = "Session: Lock" })

hl.bind("SUPER + I", hl.dsp.global("quickshell:packageInstallerToggle"),
    { description = "Shell: Package installer" })

hl.bind("SUPER + S", hl.dsp.exec_cmd(settingsApp),
    { description = "App: Settings app" })
hl.bind("SUPER + SHIFT + ALT + G", function()
    local w = hl.get_active_window()
    if w == nil then
        hl.notification.create({ text = "No active window", duration = 2000 })
        return
    end
    local at = w.at
    local size = w.size
    local atStr = type(at) == "table" and ("x=" .. tostring(at.x or at[1]) .. " y=" .. tostring(at.y or at[2])) or tostring(at)
    local sizeStr = type(size) == "table" and ("w=" .. tostring(size.x or size[1]) .. " h=" .. tostring(size.y or size[2])) or tostring(size)
    hl.notification.create({ text = "at: " .. atStr .. " | size: " .. sizeStr, duration = 4000 })
end, { description = "Geometry test: read" })

hl.bind("SUPER + SHIFT + ALT + H", function()
    local w = hl.get_active_window()
    if w == nil then return end
    w.at = { 100, 100 }
    w.size = { 800, 600 }
end, { description = "Geometry test: write" })
