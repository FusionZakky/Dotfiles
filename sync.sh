#!/usr/bin/env bash
# ~/.dotfiles/sync.sh: pull live drift back into the repo and refresh the package lists.
#
# Some apps (ii saving config.json, KDE apps saving *rc files, xdg-mime) save by REPLACING
# the file, which swaps our symlink for a real file. `stow --adopt` moves that real file
# into the repo (the LIVE version wins) and restores the symlink; git then shows the change.
# Do NOT run this on a fresh machine before the links exist: that machine's default files
# would overwrite the repo. Use install.sh there.

set -euo pipefail
cd "$(dirname "$0")"

command -v stow &>/dev/null || { echo "GNU Stow not found: sudo pacman -S stow"; exit 1; }

EXCLUDE=("system" "packages")
PACKAGES=()
for d in */; do
  name="${d%/}"
  keep=true
  for ex in "${EXCLUDE[@]}"; do
    [[ "$name" == "$ex" ]] && keep=false
  done
  $keep && PACKAGES+=("$name")
done

echo "Syncing: ${PACKAGES[*]}"
if ! out=$(stow --adopt -v -t "$HOME" "${PACKAGES[@]}" 2>&1); then
  echo "$out"
  echo "stow reported a problem; nothing else was touched"
  exit 1
fi
echo "$out" | grep -v '^LINK: ' || true
echo "new links created: $(echo "$out" | grep -c '^LINK: ' || true)"

mkdir -p packages
pacman -Qqen > packages/pacman-native.txt
pacman -Qqem > packages/pacman-foreign.txt
if command -v uv &>/dev/null; then
  uv tool list 2>/dev/null | awk '/^[^ -]/{print $1}' > packages/uv-tools.txt
fi

git status --short
