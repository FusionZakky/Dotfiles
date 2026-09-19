#!/usr/bin/env bash
# ~/.dotfiles/uninstall.sh — reverses install.sh: removes the symlinks.
# The real content stays safe in this repo either way, but the live paths
# (e.g. ~/.config/hypr) will simply stop existing once unstowed, since they
# were pure symlinks — don't run this without a reason.

set -euo pipefail
cd "$(dirname "$0")"

if ! command -v stow &>/dev/null; then
  echo "GNU Stow not found — nothing to unstow with."
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

echo "Unstowing: ${PACKAGES[*]}"
stow -v -D -t "$HOME" "${PACKAGES[@]}"

echo "Done. Copy from this repo if you need the real files back at those paths."
