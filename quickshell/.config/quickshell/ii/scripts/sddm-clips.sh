#!/usr/bin/env bash
# Records a short clip of each given theme in the greeter's test mode, for QML-animated themes the panel cannot play itself.
# usage: sddm-clips.sh <name> <path> [<name> <path> ...]     SDDM_CLIP_SECONDS=8 sets the length per theme
export LC_ALL=C
cache="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
clips="$cache/sddm_clips"
mkdir -p "$clips"
secs="${SDDM_CLIP_SECONDS:-8}"
note() { notify-send -a Shell -h string:x-canonical-private-synchronous:sddm-clips "SDDM previews" "$1"; }
for tool in wf-recorder ffmpeg hyprctl jq sddm-greeter-qt6; do
    command -v "$tool" >/dev/null 2>&1 || { note "Missing tool: $tool"; exit 2; }
done
# the picker panel is an overlay and would end up in the recording
if hyprctl layers -j 2>/dev/null | grep -q 'quickshell:wallpaperPicker'; then
    qs -c ii ipc call wallpaperPicker toggle >/dev/null 2>&1; sleep 0.7
fi
# time to move the mouse pointer out of the frame (it would be in every clip), and clear leftovers from interrupted runs
sleep "${SDDM_CLIP_WAIT:-3}"
rm -f "$clips"/*.raw.mp4 "$clips"/*.tmp.mp4
geometry_of() { hyprctl clients -j 2>/dev/null | jq -r --argjson pid "$1" '[.[] | select(.pid == $pid)][0] | select(. != null) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'; }
record_one() {
    local name="$1" path="$2" gpid geom i raw="$clips/$1.raw.mp4" out="$clips/$1.mp4"
    sddm-greeter-qt6 --test-mode --theme "$path" >/dev/null 2>&1 </dev/null &
    gpid=$!
    geom=""
    for i in $(seq 1 80); do
        kill -0 "$gpid" 2>/dev/null || break
        geom=$(geometry_of "$gpid"); [ -n "$geom" ] && break
        sleep 0.25
    done
    if [ -z "$geom" ]; then kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null; return 1; fi
    rm -f "$raw"
    timeout -s INT "$secs" wf-recorder -g "$geom" -f "$raw" >/dev/null 2>&1 </dev/null
    kill "$gpid" 2>/dev/null; wait "$gpid" 2>/dev/null
    [ -s "$raw" ] || return 1
    ffmpeg -nostdin -y -loglevel error -i "$raw" -vf "fps=30,scale=1280:-2" -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p -an -movflags +faststart "$out.tmp.mp4" </dev/null
    rm -f "$raw"
    [ -s "$out.tmp.mp4" ] && mv -f "$out.tmp.mp4" "$out"
}
failed=""
while [ $# -ge 2 ]; do
    record_one "$1" "$2" || failed="$failed $1"
    shift 2
done
[ -n "$failed" ] && note "Clip recording failed for:$failed"
sleep 1
qs -c ii ipc call wallpaperPicker open >/dev/null 2>&1
