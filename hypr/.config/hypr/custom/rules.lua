

-- imv quick-preview window (opened by fast-preview.sh): floating, centred, 60% of the monitor
hl.window_rule({match = {class = "^(imv)$" }, float = true})
hl.window_rule({match = {class = "^(imv)$" }, center = true})
hl.window_rule({match = {class = "^(imv)$" }, size = {"(monitor_w*0.60)", "(monitor_h*0.60)"} })
hl.window_rule({match = {class = "^(imv)$" }, dim_around = true})

-- HyprGlass (foot and kitty only): the tags live in the permanent config so a reload cannot drop them
hl.window_rule({ match = { class = "foot" }, tag = "+hyprglass_enabled" })
hl.window_rule({ match = { class = "foot" }, tag = "+hyprglass_preset_dark_crimson" })
hl.window_rule({ match = { class = "kitty" }, tag = "+hyprglass_enabled" })
hl.window_rule({ match = { class = "kitty" }, tag = "+hyprglass_preset_dark_crimson" })
