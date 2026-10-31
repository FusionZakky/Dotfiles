
-- >>> early wallpaper >>>
-- Shows the wallpaper straight away at login until Quickshell is up (does nothing on config reloads).
hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/early-wallpaper")
-- <<< early wallpaper <<<

-- >>> tablet mode init >>>
-- Re-reads the real fold position at login and on config reloads, so tablet UI can never start out stale.
hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/tablet-mode init")
-- <<< tablet mode init <<<
