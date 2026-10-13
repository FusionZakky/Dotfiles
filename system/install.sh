#!/usr/bin/env bash
# Installs the root-owned files under ./etc into /etc (asks for sudo).
# Not stowed on purpose: these need root and must be real files, not symlinks.
set -euo pipefail
cd "$(dirname "$0")"
find etc -type f | while read -r f; do
  sudo install -Dm644 "$f" "/$f"
  echo "installed /$f"
done
sudo udevadm control --reload
sudo udevadm trigger
echo "udev rules reloaded. modprobe changes apply after the next boot (and mkinitcpio -P if they are in the initramfs)."
echo "NOTE: 91-kbd-backlight-sync.rules hardcodes /home/zakkaria/.local/bin/kbd-backlight-sync."
