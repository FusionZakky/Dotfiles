

-- Put ~/.local/bin on PATH for everything Hyprland spawns (launcher, fuzzel, Quickshell, keybind commands).
-- Hyprland's own PATH comes from the SDDM login and does not include it. Guarded so reloads don't keep prepending.
local local_bin = os.getenv("HOME") .. "/.local/bin"
local cur_path = os.getenv("PATH") or ""
if not cur_path:find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. cur_path)
end
