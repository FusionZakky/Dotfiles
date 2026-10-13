#!/bin/bash

# 1. BULLETPROOF TOGGLE: Fire at all targets. If anything dies, exit instantly.
killed=0
killall -9 imv 2>/dev/null && killed=1
killall -9 imv-wayland 2>/dev/null && killed=1
killall -9 sushi 2>/dev/null && killed=1
killall -9 gjs 2>/dev/null && killed=1

if [ "$killed" -eq 1 ]; then
    exit 0
fi

# 2. DYNAMIC WAYLAND VARIABLES
export WAYLAND_DISPLAY=$(systemctl --user show-environment | grep '^WAYLAND_DISPLAY=' | cut -d= -f2)
export XDG_RUNTIME_DIR=/run/user/$(id -u)

MIME=$(file -b --mime-type "$1")

launch_imv() {
    setsid imv "$1" </dev/null &> /dev/null &
    exit 0
}

# 3. INSTANT PDF SNAPSHOT
if [[ "$MIME" == application/pdf ]]; then
    pdftoppm -f 1 -l 1 -singlefile -jpeg -scale-to 1200 "$1" /tmp/quick_preview
    launch_imv /tmp/quick_preview.jpg
fi

# 4. NATIVE IMAGES
if [[ "$MIME" == image/* ]]; then
    launch_imv "$1"
fi

# 5. INSTANT OFFICE DOCUMENT EXTRACTION
if unzip -p "$1" docProps/thumbnail.jpeg > /tmp/quick_preview.jpg 2>/dev/null && [ -s /tmp/quick_preview.jpg ]; then
    launch_imv /tmp/quick_preview.jpg
fi
if unzip -p "$1" Thumbnails/thumbnail.png > /tmp/quick_preview.png 2>/dev/null && [ -s /tmp/quick_preview.png ]; then
    launch_imv /tmp/quick_preview.png
fi

# 6. DOLPHIN CACHE FALLBACK
HASH=$(python3 -c "import urllib.parse, hashlib, sys, os; uri = 'file://' + urllib.parse.quote(os.path.abspath(sys.argv[1])); print(hashlib.md5(uri.encode('utf-8')).hexdigest())" "$1")
if [[ -f "$HOME/.cache/thumbnails/large/$HASH.png" ]]; then
    launch_imv "$HOME/.cache/thumbnails/large/$HASH.png"
elif [[ -f "$HOME/.cache/thumbnails/normal/$HASH.png" ]]; then
    launch_imv "$HOME/.cache/thumbnails/normal/$HASH.png"
fi

# 7. LAST RESORT
sushi "$1"
