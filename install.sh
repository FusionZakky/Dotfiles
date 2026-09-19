#!/usr/bin/env bash
# ~/.dotfiles/install.sh — symlinks every package here into place with GNU Stow.
# Adding a new package never requires editing this file: create a folder here
# that mirrors its real path from $HOME (e.g. newapp/.config/newapp/...) and
# rerun this script — new top-level directories are picked up automatically.
#
# If a package only tracks PART of a real directory (like illogical-impulse,
# which tracks config.json + actions/ but not the installer's own state files),
# Stow still handles it correctly — it only symlinks the paths it owns and
# leaves the rest of the directory alone. The one manual step is removing the
# specific real files/dirs being replaced before the FIRST stow run for that
# package — a one-time thing when you add it, not something this script does
# on every run.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v stow &>/dev/null; then
  echo "GNU Stow not found. Install with: sudo pacman -S stow"
  exit 1
fi

EXCLUDE=("system")
PACKAGES=()
for d in */; do
  name="${d%/}"
  keep=true
  for ex in "${EXCLUDE[@]}"; do
    [[ "$name" == "$ex" ]] && keep=false
  done
  $keep && PACKAGES+=("$name")
done

echo "Stowing: ${PACKAGES[*]}"
stow -v -t "$HOME" "${PACKAGES[@]}"

echo "Done. system/ (udev rules etc.) needs root and isn't stowed automatically — see README."
