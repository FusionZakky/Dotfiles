#!/usr/bin/env python3
# Command-line front end for hyprglass_core.py, used by the picker's Glass tab. Every call prints one JSON object.
import colorsys, json, re, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hyprglass_core as core

LAST_FILE = core.TRIAL_DIR / "auto-last.json"
PLUGIN = core.TRIAL_DIR / "hyprglass.so"
IMAGE_DIR = Path.home() / "Pictures/Wallpapers"
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}

def out(obj):
    print(json.dumps(obj))

def read_state():
    try:
        return json.loads(core.STATE_FILE.read_text())
    except Exception:
        return {}

def update_state(**changes):
    s = read_state()
    s.update(changes)
    core.STATE_FILE.write_text(json.dumps(s, indent=2))

def read_auto():
    return bool(read_state().get("auto", False))

def run(cmd, timeout):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()

def hypr_version():
    m = re.search(r"commit ([0-9a-f]{7,40})", run(["hyprctl", "version"], 4))
    return m.group(1) if m else ""

def lua_text():
    return " ".join(l for l in core.CONFIG.read_text().splitlines() if not l.strip().startswith("--"))

def load_plugin():
    # the same two steps done by hand each session: load the plugin, then apply the trial config (which tags foot and kitty windows)
    msgs = []
    if not core.plugin_loaded():
        msgs.append(run(["hyprctl", "plugin", "load", str(PLUGIN)], 20))
    msgs.append(run(["hyprctl", "eval", lua_text()], 10))
    return {"plugin": core.plugin_loaded(), "message": " | ".join(m for m in msgs if m)}

def unload_plugin():
    msg = run(["hyprctl", "plugin", "unload", str(PLUGIN)], 20)
    return {"plugin": core.plugin_loaded(), "message": msg}

def vivid_colour(path):
    # the most vivid colour of the wallpaper, darkened to a glass-friendly depth (a tint, not a spotlight)
    from PIL import Image
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((128, 128))
        q = im.quantize(colors=24, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = q.getcolors(128 * 128) or []
    total = sum(c for c, _ in counts) or 1
    best = None
    for count, idx in counts:
        r, g, b = pal[idx * 3:idx * 3 + 3]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if v < 0.28 or s < 0.30:
            continue
        score = (s ** 1.5) * (0.5 + v) * ((count / total) ** 0.35)
        if best is None or score > best[0]:
            best = (score, h, s, v)
    if best is None:
        return core.extract_image_colour(path)
    _, h, s, v = best
    r, g, b = colorsys.hsv_to_rgb(h, s, min(v, 0.55))
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))

def pick_colour(path):
    if read_state().get("mode", "vivid") == "dominant":
        return core.extract_image_colour(path)
    return vivid_colour(path)

def tick(force=False):
    path, msg = core.wallpaper_path()
    if path is None:
        return {"changed": False, "message": msg}
    try:
        stamp = path.stat().st_mtime_ns
    except OSError:
        stamp = 0
    key = f"{path}|{stamp}"
    try:
        last = json.loads(LAST_FILE.read_text()).get("key")
    except Exception:
        last = None
    if key == last and not force:
        return {"changed": False}
    rgb = pick_colour(path)
    s = core.read_config()
    s["rgb"] = rgb
    core.save_and_apply(s)
    LAST_FILE.write_text(json.dumps({"key": key}))
    return {"changed": True, "rgb": rgb, "settings": core.read_config(), "message": f"Tint {rgb} from {path.name}. " + core.LAST_MESSAGE}

def palette():
    path, msg = core.wallpaper_path()
    if path is None:
        return {"colors": [], "message": msg}
    from PIL import Image
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((96, 96))
        q = im.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = q.getcolors(96 * 96) or []
    ranked = []
    for count, idx in counts:
        r, g, b = pal[idx * 3:idx * 3 + 3]
        mx, mn = max(r, g, b), min(r, g, b)
        sat = 0 if mx == 0 else (mx - mn) / mx
        bright = (r + g + b) / 765
        score = count * (0.45 + sat) * (0.55 if bright < 0.12 or bright > 0.9 else 1.0)
        ranked.append((score, (r, g, b)))
    ranked.sort(reverse=True)
    chosen = []
    for _, c in ranked:
        if all(sum(abs(a - b) for a, b in zip(c, o)) > 90 for o in chosen):
            chosen.append(c)
        if len(chosen) == 6:
            break
    return {"colors": ["#%02X%02X%02X" % c for c in chosen], "message": "Colours of " + path.name}

def main(argv):
    core.ensure_files()
    cmd = argv[1] if len(argv) > 1 else "state"
    if cmd == "state":
        p = core.get_presets()
        st = read_state()
        wp = core.wallpaper_path()[0]
        imgs = sorted(f for f in IMAGE_DIR.iterdir() if f.suffix.lower() in IMAGE_EXTS)[:80] if IMAGE_DIR.is_dir() else []
        return {"settings": core.read_config(), "auto": bool(st.get("auto", False)), "enabled": bool(st.get("enabled", False)),
                "plugin": core.plugin_loaded(), "builtins": p["builtins"], "custom": p["custom"],
                "wallpaper": str(wp or ""), "images": [str(i) for i in imgs]}
    if cmd == "apply":
        s = core.save_and_apply(json.loads(argv[2]))
        return {"settings": s, "message": core.LAST_MESSAGE}
    if cmd == "wall":
        wp, msg = core.wallpaper_path()
        return {"rgb": pick_colour(wp) if wp else "", "message": msg}
    if cmd == "auto":
        on = argv[2] == "on"
        update_state(auto=on)
        if on:
            r = tick(force=True)
            r["auto"] = True
            return r
        return {"auto": False, "message": "Manual colour mode."}
    if cmd == "tick":
        return tick() if read_auto() else {"changed": False}
    if cmd == "palette":
        return palette()
    if cmd == "load":
        return load_plugin()
    if cmd == "enable":
        on = argv[2] == "on"
        if on:
            if not PLUGIN.is_file():
                raise ValueError("HyprGlass plugin not found: " + str(PLUGIN))
            update_state(enabled=True, hypr=hypr_version())
            r = load_plugin()
        else:
            update_state(enabled=False)
            r = unload_plugin()
        r["enabled"] = on
        return r
    if cmd == "startup":
        st = read_state()
        res = {"auto": bool(st.get("auto", False)), "enabled": bool(st.get("enabled", False)), "plugin": core.plugin_loaded()}
        if res["enabled"] and not res["plugin"]:
            if st.get("hypr") and st["hypr"] != hypr_version():
                res["message"] = "Hyprland changed since HyprGlass was enabled, so it was not loaded. Turn it on again in the Glass tab once the plugin matches."
            else:
                res.update(load_plugin())
        return res
    if cmd == "use":
        raw = json.loads(argv[2])
        s = core.normalise(raw)
        dyn = bool(raw.get("dynamic"))
        update_state(auto=dyn)
        if dyn:
            path = core.wallpaper_path()[0]
            if path is not None:
                s["rgb"] = pick_colour(path)
                try:
                    stamp = path.stat().st_mtime_ns
                except OSError:
                    stamp = 0
                LAST_FILE.write_text(json.dumps({"key": f"{path}|{stamp}"}))
        s = core.save_and_apply(s)
        return {"settings": s, "auto": dyn, "message": core.LAST_MESSAGE}
    if cmd == "preset-save":
        custom = core.get_presets()["custom"]
        name = argv[2].strip()
        if not name or len(name) > 48:
            raise ValueError("Preset name must be between 1 and 48 characters.")
        raw = json.loads(argv[3])
        entry = core.normalise(raw)
        entry["dynamic"] = bool(raw.get("dynamic"))
        custom[name] = entry
        core.PRESETS_FILE.write_text(json.dumps(custom, indent=2))
        return {"ok": True}
    if cmd == "preset-delete":
        custom = core.get_presets()["custom"]
        custom.pop(argv[2], None)
        core.PRESETS_FILE.write_text(json.dumps(custom, indent=2))
        return {"ok": True}
    raise ValueError("unknown command: " + cmd)

if __name__ == "__main__":
    try:
        out(main(sys.argv))
    except Exception as e:
        out({"error": str(e)})
        sys.exit(1)
