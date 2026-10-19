#!/usr/bin/env python3
# HyprGlass Studio: local live editor for the isolated HyprGlass trial; auto tint is sampled from the wallpaper image.
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json, re, subprocess, threading, time, webbrowser

HOME = Path.home()
TRIAL_DIR = HOME / ".local/share/hyprglass-trial"
CONFIG = TRIAL_DIR / "hyprglass.lua"
PALETTE = HOME / ".local/state/quickshell/user/generated/foot-colors.ini"
STATE_FILE = TRIAL_DIR / "editor-state.json"
PRESETS_FILE = TRIAL_DIR / "editor-presets.json"
HOST, PORT = "127.0.0.1", 8765
LOCK = threading.RLock()
AUTO = False
LAST_AUTO_RGB = None
LAST_MESSAGE = "Ready. Changes apply to HyprGlass in the running compositor."
BUILTIN_PRESETS = {
    "Dark Crimson (current favourite)": {"rgb":"#350015","alpha":40,"opacity":80,"blur":1.5,"brightness":82},
    "Soft Wine": {"rgb":"#50152C","alpha":28,"opacity":84,"blur":1.8,"brightness":86},
    "Smoky Graphite": {"rgb":"#242833","alpha":32,"opacity":84,"blur":1.7,"brightness":82},
    "Deep Plum": {"rgb":"#32133D","alpha":34,"opacity":82,"blur":1.8,"brightness":82},
}

def ensure_files():
    TRIAL_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG.exists():
        raise RuntimeError(f"Trial config not found: {CONFIG}")
    backup = CONFIG.with_name("hyprglass.lua.before-editor.bak")
    if not backup.exists():
        backup.write_text(CONFIG.read_text())
    if not PRESETS_FILE.exists():
        PRESETS_FILE.write_text(json.dumps({}, indent=2))

def read_config():
    text = CONFIG.read_text()
    tint = re.search(r"tint_color\s*=\s*0x([0-9a-fA-F]{8})", text)
    opacity = re.search(r"glass_opacity\s*=\s*([0-9.]+)", text)
    blur = re.search(r"blur_strength\s*=\s*([0-9.]+)", text)
    bright = re.search(r"brightness\s*=\s*([0-9.]+)", text)
    hx = tint.group(1) if tint else "35001566"
    return {
        "rgb": "#" + hx[:6],
        "alpha": round(int(hx[6:8], 16) * 100 / 255),
        "opacity": round(float(opacity.group(1)) * 100) if opacity else 80,
        "blur": float(blur.group(1)) if blur else 1.5,
        "brightness": round(float(bright.group(1)) * 100) if bright else 82,
    }

def normalise(s):
    rgb = str(s.get("rgb", "#350015")).strip()
    if not re.fullmatch(r"#?[0-9a-fA-F]{6}", rgb):
        raise ValueError("Colour must be a six-digit hex value, e.g. #350015.")
    return {
        "rgb": "#" + rgb.lstrip("#").upper(),
        "alpha": max(0, min(100, int(s.get("alpha", 40)))),
        "opacity": max(40, min(100, int(s.get("opacity", 80)))),
        "blur": max(0.0, min(5.0, round(float(s.get("blur", 1.5)), 2))),
        "brightness": max(50, min(100, int(s.get("brightness", 82)))),
    }

def tint_hex(s):
    rgb = s["rgb"].lstrip("#")
    alpha = round(s["alpha"] * 255 / 100)
    return f"0x{rgb}{alpha:02X}"

def make_lua(s):
    t = tint_hex(s)
    return (
        'if hl.plugin.hyprglass then local hg = hl.plugin.hyprglass; '
        'hg.preset("dark_crimson", { inherits = "subtle", '
        f'glass_opacity = {s["opacity"]/100:.2f}, blur_strength = {s["blur"]:.2f}, '
        f'dark = {{ tint_color = {t}, brightness = {s["brightness"]/100:.2f} }} '
        '}); '
        f'hg.config({{ enabled = false, default_theme = "dark", '
        f'default_preset = "dark_crimson", tint_color = {t} }}); end'
    )

def plugin_loaded():
    try:
        r = subprocess.run(["hyprctl", "plugin", "list"], capture_output=True, text=True, timeout=4)
        return "hyprglass" in (r.stdout + r.stderr).lower()
    except (OSError, subprocess.SubprocessError):
        return False

def save_and_apply(settings):
    global LAST_MESSAGE
    s = normalise(settings)
    with LOCK:
        text = CONFIG.read_text()
        t = tint_hex(s)
        replacements = [
            (r"(glass_opacity\s*=\s*)[0-9.]+", rf"\g<1>{s['opacity']/100:.2f}"),
            (r"(blur_strength\s*=\s*)[0-9.]+", rf"\g<1>{s['blur']:.2f}"),
            (r"(tint_color\s*=\s*)0x[0-9a-fA-F]{8}", rf"\g<1>{t}"),
            (r"(brightness\s*=\s*)[0-9.]+", rf"\g<1>{s['brightness']/100:.2f}"),
        ]
        for pattern, repl in replacements:
            text, n = re.subn(pattern, repl, text)
            if not n:
                raise RuntimeError(f"Couldn't update trial config field: {pattern}")
        CONFIG.write_text(text)
        result = subprocess.run(["hyprctl", "eval", make_lua(s)], capture_output=True, text=True, timeout=8)
        output = (result.stdout + result.stderr).strip()
        if result.returncode != 0 or "error:" in output.lower():
            LAST_MESSAGE = "Apply failed: " + (output or f"hyprctl exit {result.returncode}")
            raise RuntimeError(LAST_MESSAGE)
        if plugin_loaded():
            LAST_MESSAGE = "Applied live to HyprGlass. " + (output or "hyprctl returned no message.")
        else:
            LAST_MESSAGE = "Saved to the trial config, but the HyprGlass plugin is not loaded, so nothing changed on screen."
    return s

def wallpaper_path():
    """Find the active wallpaper from common wallpaper daemons or Quickshell picker state."""
    image_exts = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff", ".avif"}
    candidates = []

    def add_candidate(value, key="", bonus=0):
        if not isinstance(value, str):
            return
        value = value.strip()
        if value.startswith("file://"):
            value = value[7:]
        value = value.replace("\\\\", "\\")
        p = Path(value).expanduser()
        if not p.is_absolute() or p.suffix.lower() not in image_exts or not p.is_file():
            return
        key_l = str(key).lower()
        score = bonus
        if any(word in key_l for word in ("current", "active", "selected")):
            score += 10
        if any(word in key_l for word in ("wallpaper", "image", "path", "file", "source")):
            score += 5
        candidates.append((score, p))

    # illogical-impulse keeps the active wallpaper in its own config (swww/hyprpaper are not used here)
    try:
        ii = json.loads((HOME / ".config/illogical-impulse/config.json").read_text())
        add_candidate(ii.get("background", {}).get("wallpaperPath", ""), "active_wallpaper", 200)
    except Exception:
        pass

    # Prefer the wallpaper daemon's active image if it exposes one.
    commands = [
        (["swww", "query"], r"(?im)(?:image|path)\s*[:=]\s*(.+?\.(?:png|jpe?g|webp|bmp|tiff?|avif))\s*$"),
        (["hyprctl", "hyprpaper", "listactive"], r"(?im)wallpaper\s*=\s*(.+?\.(?:png|jpe?g|webp|bmp|tiff?|avif))\s*$"),
    ]
    for command, pattern in commands:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=2)
            for match in re.findall(pattern, result.stdout):
                add_candidate(match.strip().strip('"'), "active_wallpaper", 100)
        except (OSError, subprocess.SubprocessError):
            pass

    # Quickshell's wallpaper picker keeps state here on this setup. Walk the JSON
    # rather than assuming a particular property name/version.
    state_path = HOME / ".local/state/quickshell/wallpaper-picker-state.json"
    if state_path.is_file():
        try:
            data = json.loads(state_path.read_text())
            def walk(obj, key=""):
                if isinstance(obj, dict):
                    for k, v in obj.items():
                        walk(v, str(k))
                elif isinstance(obj, list):
                    for v in obj:
                        walk(v, key)
                else:
                    add_candidate(obj, key)
            walk(data)
        except Exception:
            pass

    # Also inspect a small set of Quickshell wallpaper service files for explicit
    # absolute image paths, in case the active path is embedded in its state/config.
    for config_path in (
        HOME / ".config/quickshell/ii/services/Wallpapers.qml",
        HOME / ".config/quickshell/ii/GlobalStates.qml",
    ):
        try:
            for match in re.findall(
                r"""(?:"|')((?:/|~/)[^"'\\n]+?\.(?:png|jpe?g|webp|bmp|tiff?|avif))(?:"|')""",
                config_path.read_text(errors="replace"),
                re.IGNORECASE,
            ):
                add_candidate(match, "wallpaper_config", 1)
        except OSError:
            pass

    if not candidates:
        return None, (
            "Couldn't identify the active wallpaper. Expected a path from swww, "
            "hyprpaper, or ~/.local/state/quickshell/wallpaper-picker-state.json."
        )
    # Higher-scored active/selected wallpaper properties take precedence.
    candidates.sort(key=lambda item: item[0], reverse=True)
    return candidates[0][1], "Active wallpaper image: " + str(candidates[0][1])


def extract_image_colour(image_path):
    """Return a representative, reasonably saturated colour from the wallpaper."""
    # Pillow path: downsample and quantise, then prefer a frequent non-grey midtone.
    try:
        from PIL import Image
        with Image.open(image_path) as im:
            im = im.convert("RGB")
            im.thumbnail((96, 96))
            quantized = im.quantize(colors=24, method=Image.Quantize.MEDIANCUT)
            palette = quantized.getpalette()
            counts = quantized.getcolors(96 * 96) or []
        ranked = []
        for count, index in counts:
            r, g, b = palette[index * 3:index * 3 + 3]
            mx, mn = max(r, g, b), min(r, g, b)
            brightness = (r + g + b) / 765
            saturation = 0 if mx == 0 else (mx - mn) / mx
            # Prefer colours that are visible and chromatic, but retain frequency.
            score = count * (0.45 + saturation) * (0.55 if brightness < 0.12 or brightness > 0.9 else 1.0)
            ranked.append((score, count, r, g, b))
        if ranked:
            _, _, r, g, b = max(ranked)
            return f"#{r:02X}{g:02X}{b:02X}"
    except ImportError:
        pass
    except Exception as e:
        pillow_error = str(e)
    else:
        pillow_error = "Pillow returned no usable colours"

    # ImageMagick fallback. This keeps the editor dependency-light and uses tools
    # commonly available on Linux; no terminal palette is read.
    for binary in ("magick", "convert"):
        try:
            command = [binary, str(image_path), "-resize", "80x80!", "-colors", "24",
                       "-format", "%c", "histogram:info:-"]
            result = subprocess.run(command, capture_output=True, text=True, timeout=12)
            if result.returncode != 0:
                continue
            ranked = []
            for line in result.stdout.splitlines():
                m = re.search(r"^\s*(\d+):.*?#([0-9a-fA-F]{6})", line)
                if not m:
                    continue
                count, hx = int(m.group(1)), m.group(2)
                r, g, b = (int(hx[i:i+2], 16) for i in (0, 2, 4))
                mx, mn = max(r, g, b), min(r, g, b)
                brightness = (r + g + b) / 765
                saturation = 0 if mx == 0 else (mx - mn) / mx
                score = count * (0.45 + saturation) * (0.55 if brightness < 0.12 or brightness > 0.9 else 1.0)
                ranked.append((score, hx))
            if ranked:
                return "#" + max(ranked)[1].upper()
        except (OSError, subprocess.SubprocessError):
            continue
    raise RuntimeError(
        "Found the wallpaper, but couldn't sample its colours. Install python-pillow "
        "(python-pillow on Arch) or ImageMagick (imagemagick), then restart the editor."
    )


def wallpaper_rgb():
    path, source_message = wallpaper_path()
    if path is None:
        return None, source_message
    try:
        colour = extract_image_colour(path)
        return colour, f"{source_message}; extracted tint {colour}"
    except Exception as e:
        return None, str(e)

def get_state():
    global LAST_AUTO_RGB, LAST_MESSAGE
    s = read_config()
    if AUTO:
        rgb, msg = wallpaper_rgb()
        if rgb:
            if rgb != LAST_AUTO_RGB or rgb != s["rgb"]:
                s["rgb"] = rgb
                try:
                    save_and_apply(s)
                    LAST_AUTO_RGB = rgb
                    LAST_MESSAGE = msg + " (applied live)"
                except Exception as e:
                    LAST_MESSAGE = f"Auto-colour read, but apply failed: {e}"
            else:
                LAST_MESSAGE = msg
        else:
            LAST_MESSAGE = msg
    return {"settings": read_config(), "auto": AUTO, "message": LAST_MESSAGE}

def get_presets():
    try:
        custom = json.loads(PRESETS_FILE.read_text())
    except Exception:
        custom = {}
    return {"builtins": BUILTIN_PRESETS, "custom": custom}

PAGE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HyprGlass Studio</title>
<style>
:root{color-scheme:dark;--bg:#101014;--line:#3a2a37;--text:#f4edf3;--muted:#b4a5b2;--accent:#cf557f}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at 5% 0%,#381426 0,transparent 38%),var(--bg);color:var(--text);font:14px/1.45 system-ui,sans-serif}
main{max-width:1180px;margin:auto;padding:28px 24px 38px}.head{display:flex;align-items:center;justify-content:space-between;gap:18px;margin-bottom:20px}
h1{font-size:25px;letter-spacing:-.6px;margin:0}.sub{color:var(--muted);margin-top:4px}.pill{border:1px solid #6d3c55;border-radius:999px;padding:6px 10px;color:#f3b7ce;font-size:12px;white-space:nowrap}
.layout{display:grid;grid-template-columns:minmax(0,1fr) minmax(310px,.86fr);gap:18px}.panel{background:linear-gradient(145deg,#201a23ed,#17151bee);border:1px solid var(--line);border-radius:18px;padding:19px;box-shadow:0 14px 45px #0003}
.panel h2{font-size:15px;margin:0 0 15px}.field{margin:17px 0}.fieldtop{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:8px}.fieldtop label{font-weight:600}.val{font-variant-numeric:tabular-nums;color:#f2a8c3;font-size:12px}
input[type=range]{width:100%;accent-color:var(--accent)}input[type=color]{width:42px;height:36px;border:1px solid #5b4555;background:#151219;border-radius:9px;padding:3px}
input[type=text],select{background:#100e13;border:1px solid #55404f;border-radius:9px;color:var(--text);padding:9px 10px;font:inherit}
.hexrow{display:flex;align-items:center;gap:10px}.hexrow input[type=text]{width:125px;text-transform:uppercase}.hint{color:var(--muted);font-size:12px}
.toggle{display:flex;align-items:center;gap:10px;background:#2a1b27;border:1px solid #583448;padding:12px;border-radius:12px}.toggle input{accent-color:var(--accent);width:17px;height:17px}.toggle label{font-weight:650}.toggle small{display:block;color:var(--muted);font-weight:400;margin-top:2px}
.previewwall{height:300px;border-radius:13px;overflow:hidden;position:relative;background:linear-gradient(125deg,#121b32,#573047 40%,#c26c66 63%,#1c182b);padding:22px;isolation:isolate}
.previewwall:before{content:"";position:absolute;inset:-20px;z-index:-2;background:radial-gradient(circle at 75% 28%,#f7c48b 0 7%,transparent 8%),radial-gradient(ellipse at 68% 72%,#6b789b 0 18%,transparent 19%),linear-gradient(135deg,#131e38,#8b475b 52%,#d39a72);filter:blur(1px)}
.previewlabel{font-size:10px;text-transform:uppercase;letter-spacing:1.6px;color:#fcecf4a8;margin-bottom:13px}
.glass{height:235px;border:1px solid #ffffff3a;border-radius:13px;padding:17px 18px;box-shadow:0 12px 30px #0005;backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);overflow:hidden}
.glass h3{margin:0 0 12px;font:600 13px ui-monospace,monospace}.line{height:7px;border-radius:8px;background:#ffffff2e;margin:9px 0;width:90%}.line.short{width:58%}.line.med{width:75%}
.previewnote{color:var(--muted);font-size:12px;margin:10px 0 0}.buttons{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
button{border:1px solid #624054;background:#30212d;color:var(--text);border-radius:10px;padding:9px 12px;font:600 12px system-ui;cursor:pointer}button:hover{border-color:#c65a83;background:#422637}button.primary{background:linear-gradient(135deg,#a63860,#6f2445);border-color:#c35a80}button.ghost{background:transparent}
.row{display:flex;gap:9px;align-items:center}.row select{flex:1;min-width:0}.status{margin-top:16px;background:#131116;border:1px solid #3a303b;border-radius:10px;padding:10px 12px;color:#cbbdc9;font-size:12px;min-height:40px;overflow-wrap:anywhere}.status.ok{border-color:#375642;color:#b8e5c4}.status.err{border-color:#7a3547;color:#ffb6c6}
.sectionlabel{font-size:11px;text-transform:uppercase;letter-spacing:1.1px;color:#caa9bb;margin:19px 0 7px}.foot{color:#958793;font-size:11px;margin-top:15px}
@media(max-width:850px){.layout{grid-template-columns:1fr}.head{align-items:flex-start;flex-direction:column}.previewwall{height:270px}}
</style></head><body><main>
<div class="head"><div><h1>HyprGlass <span style="color:#e17da2">Studio</span></h1><div class="sub">Live controls for your isolated dark-crimson trial · Hyprland</div></div><div class="pill">LOCAL PROTOTYPE · NO EXTRA PACKAGES</div></div>
<div class="layout"><section class="panel">
<h2>Glass appearance</h2>
<div class="toggle"><input id="auto" type="checkbox"><div><label for="auto">Adapt tint to wallpaper colours</label><small>Samples the active wallpaper image and reapplies its representative colour while this editor runs.</small></div></div>
<div class="sectionlabel">Tint colour</div><div class="field"><div class="hexrow"><input id="color" type="color" value="#350015"><input id="hex" type="text" value="#350015" maxlength="9" spellcheck="false"><span class="hint">Hex RGB</span></div></div>
<div class="field"><div class="fieldtop"><label for="alpha">Tint strength</label><span class="val" id="alphaVal">40%</span></div><input id="alpha" type="range" min="0" max="100" value="40"><div class="fieldtop"><span class="hint">Subtle</span><span class="hint">Strong</span></div></div>
<div class="field"><div class="fieldtop"><label for="opacity">Glass opacity</label><span class="val" id="opacityVal">80%</span></div><input id="opacity" type="range" min="40" max="100" value="80"><div class="fieldtop"><span class="hint">More see-through</span><span class="hint">More solid</span></div></div>
<div class="field"><div class="fieldtop"><label for="blur">Blur strength</label><span class="val" id="blurVal">1.50</span></div><input id="blur" type="range" min="0" max="5" step="0.1" value="1.5"><div class="fieldtop"><span class="hint">Crisp background</span><span class="hint">Softer background</span></div></div>
<div class="field"><div class="fieldtop"><label for="brightness">Darkness / brightness</label><span class="val" id="brightnessVal">82%</span></div><input id="brightness" type="range" min="50" max="100" value="82"><div class="fieldtop"><span class="hint">Darker</span><span class="hint">Brighter</span></div></div>
<div class="status" id="status">Connecting to HyprGlass…</div><div class="buttons"><button class="primary" id="apply">Apply now</button><button id="reset">Reset favourite</button><button class="ghost" id="revert">Reload saved config</button></div>
</section><section class="panel">
<h2>Preview & presets</h2><div class="previewwall"><div class="previewlabel">Example background</div><div class="glass" id="glass"><h3>zakkaria@archlinux: ~</h3><div class="line"></div><div class="line med"></div><div class="line short"></div><div class="line"></div><div class="line med"></div><div class="line short"></div><div style="margin-top:15px;color:#ffffffb8;font:11px ui-monospace,monospace">Text stays readable over a busy background.</div></div></div>
<div class="previewnote">Visual approximation only. Kitty shows the real compositor effect; keep it open to judge the actual result.</div>
<div class="sectionlabel">Load a preset</div><div class="row"><select id="preset"></select><button id="loadPreset">Load</button></div>
<div class="sectionlabel">Save your own preset</div><div class="row"><input id="presetName" type="text" placeholder="e.g. Muted rose" style="flex:1;min-width:0"><button id="savePreset">Save</button></div>
<div class="buttons"><button id="autoOn">Use wallpaper colours</button><button id="autoOff">Manual colours</button></div>
<div class="foot">Writes only to ~/.local/share/hyprglass-trial/. The existing Quickshell config and generated palette are not edited.</div>
</section></div></main>
<script>
const $=id=>document.getElementById(id);let applying=false,debounce=null;
function values(){return {rgb:$('hex').value,alpha:+$('alpha').value,opacity:+$('opacity').value,blur:+$('blur').value,brightness:+$('brightness').value};}
function setValues(s){$('color').value=s.rgb;$('hex').value=s.rgb.toUpperCase();for(const k of ['alpha','opacity','blur','brightness'])$(k).value=s[k];updateLabels();preview();}
function updateLabels(){for(const k of ['alpha','opacity','brightness'])$(k+'Val').textContent=$(''+k).value+'%';$('blurVal').textContent=(+$('blur').value).toFixed(2);}
function preview(){const s=values(),rgb=s.rgb.replace('#','');if(!/^[0-9a-fA-F]{6}$/.test(rgb))return;const r=parseInt(rgb.slice(0,2),16),g=parseInt(rgb.slice(2,4),16),b=parseInt(rgb.slice(4,6),16),a=(s.alpha/100)*(s.opacity/100);$('glass').style.background=`rgba(${r},${g},${b},${a})`;$('glass').style.backdropFilter=`blur(${Math.max(0,s.blur*5)}px) brightness(${s.brightness/100})`;$('glass').style.webkitBackdropFilter=$('glass').style.backdropFilter;}
function status(msg,kind=''){const e=$('status');e.textContent=msg;e.className='status '+kind;}
async function api(path,data){const r=await fetch(path,{method:data?'POST':'GET',headers:data?{'Content-Type':'application/json'}:{},body:data?JSON.stringify(data):undefined});const j=await r.json();if(!r.ok)throw Error(j.error||'Request failed');return j;}
async function apply(){if(applying)return;applying=true;try{const j=await api('/api/apply',{settings:values()});status(j.message||'Applied live.','ok')}catch(e){status(e.message,'err')}finally{applying=false}}
function scheduleApply(){updateLabels();preview();if($('auto').checked)return;clearTimeout(debounce);debounce=setTimeout(apply,220)}
$('color').addEventListener('input',()=>{$('hex').value=$('color').value.toUpperCase();scheduleApply()});
$('hex').addEventListener('change',()=>{let v=$('hex').value.trim();if(!v.startsWith('#'))v='#'+v;if(/^#[0-9a-fA-F]{6}$/.test(v)){$('hex').value=v.toUpperCase();$('color').value=v;scheduleApply()}else status('Enter a valid six-digit colour, e.g. #350015.','err')});
for(const k of ['alpha','opacity','blur','brightness'])$(k).addEventListener('input',scheduleApply);
$('apply').onclick=apply;
$('reset').onclick=async()=>{setValues({rgb:'#350015',alpha:40,opacity:80,blur:1.5,brightness:82});$('auto').checked=false;try{await api('/api/auto',{enabled:false});await apply()}catch(e){status(e.message,'err')}};
$('revert').onclick=async()=>{try{const j=await api('/api/state');setValues(j.settings);$('auto').checked=j.auto;status('Reloaded saved trial configuration.','ok')}catch(e){status(e.message,'err')}};
async function refreshPresets(){try{const j=await api('/api/presets'),sel=$('preset');sel.innerHTML='';for(const [group,obj] of [['Built-in',j.builtins],['Saved by you',j.custom]])for(const [name,s] of Object.entries(obj)){const o=document.createElement('option');o.value=JSON.stringify(s);o.textContent=group+' · '+name;sel.appendChild(o)}}catch(e){status(e.message,'err')}}
$('loadPreset').onclick=async()=>{try{setValues(JSON.parse($('preset').value));$('auto').checked=false;await api('/api/auto',{enabled:false});await apply()}catch(e){status(e.message,'err')}};
$('savePreset').onclick=async()=>{const name=$('presetName').value.trim();if(!name){status('Give the preset a name first.','err');return}try{await api('/api/presets',{name,settings:values()});$('presetName').value='';await refreshPresets();status('Preset saved.','ok')}catch(e){status(e.message,'err')}};
async function toggleAuto(enabled){$('auto').checked=enabled;try{const j=await api('/api/auto',{enabled});if(j.settings)setValues(j.settings);status(j.message||'Wallpaper colour mode updated.','ok')}catch(e){status(e.message,'err')}}
$('auto').onchange=()=>toggleAuto($('auto').checked);$('autoOn').onclick=()=>toggleAuto(true);$('autoOff').onclick=()=>toggleAuto(false);
async function boot(){try{const j=await api('/api/state');setValues(j.settings);$('auto').checked=j.auto;status(j.message,'ok');await refreshPresets()}catch(e){status(e.message,'err')}}
setInterval(async()=>{try{const j=await api('/api/state');if(j.auto){$('auto').checked=true;setValues(j.settings);status(j.message,'ok')}}catch(e){}},2200);boot();
</script></body></html>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass
    def send_json(self, code, obj):
        data=json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",str(len(data))); self.send_header("Cache-Control","no-store")
        self.end_headers(); self.wfile.write(data)
    def body(self):
        n=int(self.headers.get("Content-Length","0"))
        if n>100_000: raise ValueError("Request too large")
        return json.loads(self.rfile.read(n) or b"{}")
    def do_GET(self):
        if self.path=="/":
            data=PAGE.encode(); self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8")
            self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
        elif self.path=="/api/state":
            try: self.send_json(200,get_state())
            except Exception as e: self.send_json(500,{"error":str(e)})
        elif self.path=="/api/presets": self.send_json(200,get_presets())
        else: self.send_json(404,{"error":"Not found"})
    def do_POST(self):
        global AUTO,LAST_MESSAGE,LAST_AUTO_RGB
        try:
            data=self.body()
            if self.path=="/api/apply":
                s=save_and_apply(data.get("settings",{})); self.send_json(200,{"settings":s,"message":LAST_MESSAGE})
            elif self.path=="/api/auto":
                AUTO=bool(data.get("enabled")); STATE_FILE.write_text(json.dumps({"auto":AUTO},indent=2))
                if AUTO:
                    rgb,msg=wallpaper_rgb()
                    if not rgb: self.send_json(400,{"error":msg}); return
                    s=read_config(); s["rgb"]=rgb; save_and_apply(s); LAST_AUTO_RGB=rgb; LAST_MESSAGE=msg+" (applied live)"
                else: LAST_MESSAGE="Manual colour mode. Tint is controlled by the colour picker and hex field."
                self.send_json(200,{"settings":read_config(),"auto":AUTO,"message":LAST_MESSAGE})
            elif self.path=="/api/presets":
                name=str(data.get("name","")).strip()
                if not name or len(name)>48: raise ValueError("Preset name must be between 1 and 48 characters.")
                presets=get_presets()["custom"]; presets[name]=normalise(data.get("settings",{}))
                PRESETS_FILE.write_text(json.dumps(presets,indent=2)); self.send_json(200,{"ok":True})
            else: self.send_json(404,{"error":"Not found"})
        except Exception as e: self.send_json(400,{"error":str(e)})

def auto_loop():
    global LAST_AUTO_RGB,LAST_MESSAGE
    while True:
        time.sleep(2)
        if not AUTO: continue
        try:
            rgb,msg=wallpaper_rgb()
            if rgb and rgb!=LAST_AUTO_RGB:
                s=read_config(); s["rgb"]=rgb; save_and_apply(s)
                LAST_AUTO_RGB=rgb; LAST_MESSAGE=msg+" (applied live)"
        except Exception as e: LAST_MESSAGE=f"Auto-colour update failed: {e}"

def main():
    global AUTO
    ensure_files()
    try: AUTO=bool(json.loads(STATE_FILE.read_text()).get("auto",False))
    except Exception: AUTO=False
    server=ThreadingHTTPServer((HOST,PORT),Handler)
    threading.Thread(target=auto_loop,daemon=True).start()
    url=f"http://{HOST}:{PORT}/"
    print("HyprGlass Studio"); print(f"Local UI: {url}"); print(f"Trial config: {CONFIG}")
    print("Only the isolated trial config is edited. Auto mode samples the wallpaper image, not terminal colours. Press Ctrl+C here to stop.")
    threading.Timer(0.6,lambda:webbrowser.open(url)).start()
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()

if __name__=="__main__": main()
