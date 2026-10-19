#!/usr/bin/env bash
# EXPERIMENTAL. Runs each theme in the real greeter's test mode, screenshots the window, and closes it again.
# usage: sddm-capture.sh <name> <path> [<name> <path> ...]
# Needs grim, jq, hyprctl, sddm-greeter-qt6. If wtype is installed it also captures the screen after a key press
# (many themes show a lock/clock screen first and the login box second). Set SDDM_CAPTURE_DELAY=8 to wait longer per theme.
export LC_ALL=C
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
caps="$cache/sddm_captures"
mkdir -p "$caps"
delay="${SDDM_CAPTURE_DELAY:-2}"

note() { notify-send -a Shell -h string:x-canonical-private-synchronous:sddm-capture "SDDM previews" "$1"; }
reopen() { qs -c ii ipc call wallpaperPicker open >/dev/null 2>&1; }

for tool in grim jq hyprctl sddm-greeter-qt6; do
    command -v "$tool" >/dev/null 2>&1 || { note "Missing tool: $tool"; reopen; exit 2; }
done

geometry_of() { # pid -> "x,y WxH"
    hyprctl clients -j 2>/dev/null | jq -r --argjson pid "$1" '[.[] | select(.pid == $pid)][0] | select(. != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

capture_one() {
    local name="$1" path="$2" gpid geom i t1 t2 active d tot
    sddm-greeter-qt6 --test-mode --theme "$path" >/dev/null 2>&1 </dev/null &
    gpid=$!
    geom=""
    for i in $(seq 1 80); do
        kill -0 "$gpid" 2>/dev/null || break
        geom=$(geometry_of "$gpid")
        [ -n "$geom" ] && break
        sleep 0.25
    done
    if [ -z "$geom" ]; then kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null; return 1; fi

    sleep "$delay"   # let intro animations settle
    geom=$(geometry_of "$gpid")
    if [ -z "$geom" ]; then kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null; return 1; fi
    t1="$caps/$name.1.png.tmp"
    if grim -g "$geom" "$t1" 2>/dev/null && [ -s "$t1" ]; then
        mv -f "$t1" "$caps/$name.1.png"
    else
        rm -f "$t1"; kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null; return 1
    fi

    rm -f "$caps/$name.2.png"
    if command -v wtype >/dev/null 2>&1; then
        active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // 0')
        if [ "$active" = "$gpid" ]; then   # only type if the greeter really has focus
            wtype -k space
            sleep 2
            t2="$caps/$name.2.png.tmp"
            if grim -g "$geom" "$t2" 2>/dev/null && [ -s "$t2" ]; then
                d=$(magick compare -metric AE -fuzz 3% "$caps/$name.1.png" "$t2" null: 2>&1 </dev/null); d=${d%% *}
                tot=$(magick identify -format '%[fx:w*h]' "$caps/$name.1.png" 2>/dev/null </dev/null)
                if [[ "$d" =~ ^[0-9]+([.][0-9]+)?$ ]] && [ -n "$tot" ] && awk -v d="$d" -v t="$tot" 'BEGIN { exit !(d > t * 0.005) }'; then
                    mv -f "$t2" "$caps/$name.2.png"   # only keep it if it really looks different
                else
                    rm -f "$t2"
                fi
            fi
        fi
    fi
    kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null
    return 0
}

total=$(( $# / 2 )); n=0; okc=0; failed=""
while [ $# -ge 2 ]; do
    n=$(( n + 1 ))
    if capture_one "$1" "$2"; then okc=$(( okc + 1 )); else failed="$failed $1"; fi
    printf '%s\n' "$1" >> "$cache/sddm-capture-tried.txt"
    shift 2
done
[ -n "$failed" ] && note "Capture failed for:$failed"
sleep 1
reopen
