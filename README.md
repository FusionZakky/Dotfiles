# Taeko Dotfiles

Personal Hyprland + Quickshell desktop config for a Chromebook (Taeko), running Arch Linux. Based on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("ii"), heavily modified.

## Structure

Each top-level folder is a [GNU Stow](https://www.gnu.org/software/stow/) package — the path inside it mirrors its real location relative to `$HOME` (e.g. `hypr/.config/hypr/...` becomes `~/.config/hypr/...`). `install.sh` stows everything automatically; a new package just needs a folder here, no script edits.

## Install / uninstall

```bash
./install.sh     # stows everything (except system/) into place
./uninstall.sh   # removes the symlinks; repo content is untouched either way
```

Requires `stow` (`sudo pacman -S stow`). `system/` needs root and is copied manually.

## Whats excluded, and why

- **Secrets** — `quickshell/.config/quickshell/ii/wallpaper-picker-keys.json` holds real API keys (wallhaven, unsplash, pexels) and is gitignored; only a redacted `.example` is tracked. Recreate it with real values after cloning. AI Assistant (Gemini/OpenAI/Mistral) keys go through the system keyring instead of a file, so there is nothing to track for those.
- **iis own installer state** — `installed_listfile`/`installed_true` under `illogical-impulse/` are the installers own bookkeeping, not config, so they are not tracked.
- **`config.json`** silently strips any unrecognized field on save — do not hand-add custom keys to it.

## Whats changed from stock ii

- Restyled bar ("Bar Islands" look)
- Custom package-installer popup
- Custom wallpaper picker (wallhaven/unsplash/pexels backed)
- Taeko-specific WirePlumber audio profile override
- Keyboard-backlight scripts (`kbd-backlight-set`/`-cycle`/`-sync`) for a device with no ambient light sensor

## Known quirks

Two symlinks under `hypr/.config/hypr/wallpapers/` use absolute, username-specific paths. Fine as long as this stays on the same machine/user; if that ever changes, recreate them:

```bash
ln -sf ~/Pictures/Wallpapers ~/.dotfiles/hypr/.config/hypr/wallpapers/Wallpapers
ln -sf ~/Pictures/Wallpapers/crimson-foliage.png ~/.dotfiles/hypr/.config/hypr/wallpapers/crimson-foliage.png
```
