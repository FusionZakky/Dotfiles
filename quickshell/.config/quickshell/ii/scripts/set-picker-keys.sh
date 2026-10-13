#!/usr/bin/env bash
# Updates the picker's API keys. Typed values are hidden and never reach shell history.
# Press Enter at a prompt to keep the current value for that source.
f="$HOME/.config/quickshell/ii/wallpaper-picker-keys.json"
[ -f "$f" ] || echo '{}' > "$f"
tmp="$(mktemp)"
cp "$f" "$tmp"
for src in wallhaven unsplash pexels; do
    read -rsp "New $src key (Enter = keep current): " val; echo
    if [ -n "$val" ]; then
        jq --arg s "$src" --arg v "$val" '.[$s] = $v' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
    fi
done
if jq -e . "$tmp" >/dev/null; then
    install -m 600 "$tmp" "$f" && echo "Saved (owner-only). Reopen the picker with SUPER+W to use the new keys."
fi
rm -f "$tmp" "$tmp.new"
