#!/usr/bin/env bash
# Upscales an image (Lanczos) so it covers the largest monitor, but ONLY if it is smaller.
# Images that already fit are never touched. Always exits 0 so callers can chain safely.
printf '%s %s\n' fit_start "$EPOCHREALTIME" >> /tmp/wp-timing.log # WPTIMING
trap 'printf "%s %s\n" fit_end "$EPOCHREALTIME" >> /tmp/wp-timing.log' EXIT # WPTIMING
f="$1"
[ -f "$f" ] || exit 0
command -v magick >/dev/null 2>&1 || exit 0
case "${f,,}" in
    *.mp4|*.webm|*.mkv|*.avi|*.mov|*.gif) exit 0 ;;
esac
read -r screen_w screen_h < <(hyprctl monitors -j 2>/dev/null | jq -r '[([.[].width] | max), ([.[].height] | max)] | @tsv')
[ -n "$screen_w" ] && [ -n "$screen_h" ] || exit 0
read -r img_w img_h < <(magick identify -ping -format "%w %h\n" "${f}[0]" 2>/dev/null | head -n 1)
[ -n "$img_w" ] && [ -n "$img_h" ] || exit 0
if [ "$img_w" -ge "$screen_w" ] && [ "$img_h" -ge "$screen_h" ]; then
    exit 0
fi
tmp="$(mktemp --suffix=".${f##*.}")"
if magick "$f" -filter Lanczos -resize "${screen_w}x${screen_h}^" -quality 95 "$tmp" 2>/dev/null; then
    mv "$tmp" "$f" && chmod 644 "$f"
else
    rm -f "$tmp"
fi
exit 0
