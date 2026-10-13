

-- imv quick-preview window (opened by fast-preview.sh): floating, centred, 60% of the monitor
hl.window_rule({match = {class = "^(imv)$" }, float = true})
hl.window_rule({match = {class = "^(imv)$" }, center = true})
hl.window_rule({match = {class = "^(imv)$" }, size = {"(monitor_w*0.60)", "(monitor_h*0.60)"} })
hl.window_rule({match = {class = "^(imv)$" }, dim_around = true})
