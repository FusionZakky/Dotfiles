# Taeko Dotfiles

Personal Hyprland + Quickshell desktop config for a Chromebook (Taeko, Lenovo IdeaPad Flex 5 Chrome 14IAU7) running Arch Linux. Based on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("ii"), heavily modified.

## Structure

Each top-level folder is a [GNU Stow](https://www.gnu.org/software/stow/) package: the path inside it mirrors its real location under `$HOME` (`hypr/.config/hypr/...` becomes `~/.config/hypr/...`). `install.sh` stows every package automatically, so a new package only needs a new folder here.

    hypr  quickshell  illogical-impulse        Hyprland (Lua), the ii shell, ii settings
    foot  kitty  fish  bash  starship          terminals, shells, prompts
    matugen  kde-material-you-colors           wallpaper-driven theming (sources + templates)
    fuzzel  wlogout  sddm-theme                launcher, logout menu, login screen theme
    dolphin  mimeapps  xfce4                   file manager bits, default apps, xfconf stubs
    btop  cava  imv  mpv  micro  fontconfig  xdg-desktop-portal  autostart
    wireplumber  systemd-user  local-bin       audio override, localsendd unit, ~/.local/bin scripts
    system/                                    root-owned files (udev, modprobe, sddm), not stowed
    packages/                                  package lists, not stowed

## Install, sync, uninstall

    ./install.sh      # stows every package into place (fresh machine: move conflicting files away first)
    ./sync.sh         # pulls live drift back into the repo, restores links, refreshes packages/
    ./uninstall.sh    # removes the symlinks; repo content is untouched
    system/install.sh # copies the root-owned files into /etc (sudo)

Requires `stow`. Some apps (ii saving `config.json`, KDE apps saving `*rc` files, xdg-mime) save by replacing the file, which swaps the symlink for a real file. `sync.sh` fixes that with `stow --adopt` (the live file wins). Do not run `sync.sh` on a fresh machine before the links exist, or that machine's defaults overwrite the repo.

## Theming

`matugen/` holds the config and templates. On every wallpaper change matugen regenerates colour files that live in other packages (`hypr/.../hyprland/colors.lua`, `hypr/.../hyprlock/colors.conf`, `fuzzel/.../fuzzel_theme.ini`, gtk, kitty, btop, fastfetch, KDE colours). The ones Hyprland needs at startup stay tracked so a clone boots; they show up as modified after every wallpaper switch. Purely cosmetic outputs (kitty colours, btop theme) are gitignored.

## Dolphin quick preview

`dolphin/.local/share/kio/servicemenus/space-preview.desktop` adds a "Quick Preview" action that runs `~/.local/bin/fast-preview.sh`. It toggles an imv window: PDFs render page one with `pdftoppm`, Office files use their embedded thumbnail via `unzip`, images open directly, then it falls back to Dolphin's thumbnail cache and finally sushi. Needs imv, poppler, unzip, python3, sushi. Extracting and compressing in Dolphin comes from Ark (right-click, Extract / Compress); it is listed in `packages/pacman-native.txt`.

## LocalSend

`localsendd` is installed as a uv tool (see `packages/uv-tools.txt`; `~/.local/bin/localsendd` is a symlink into `~/.local/share/uv/tools`) and runs as the `localsendd.service` user unit (`systemd-user/`). The GUI is `localsend-bin` (AUR). The sidebar Transfers tab uses `LocalSendHistory.qml`, `ls_manager.py` and `ls_copier.sh` inside `quickshell/`. This setup is still evolving and may not be fully working.

## Not tracked, on purpose

- `quickshell/.../wallpaper-picker-keys.json` holds real API keys (wallhaven, unsplash, pexels) and is gitignored; only the redacted `.example` is tracked. AI assistant keys live in the system keyring.
- LocalSend's own preferences contain a TLS private key.
- ii's installer state (`installed_listfile`, `installed_true`), the login keyring, NetworkManager profiles (Wi-Fi passwords), browser/Slack/Obsidian/VS Code state.
- Generated or installer-owned files: gtk css, kdeglobals, KDE colour schemes, Kvantum, fastfetch config, `fish_variables`, zshrc.d.

## What changed from stock ii

- Restyled bar ("Bar Islands")
- Package installer popup
- Wallpaper picker (wallhaven, unsplash, pexels and more)
- Notes and Transfers tabs in the left sidebar
- Taeko WirePlumber audio override; keyboard backlight scripts and udev rules (no ambient light sensor on this device)
- `shutdown` wrapper: a bare `shutdown` powers off immediately (systemd defaults to a 1 minute delay); any arguments pass through to the real binary
- `custom/env.lua` puts `~/.local/bin` on the PATH of everything Hyprland spawns (launcher, Quickshell, keybind commands)

## Known quirks

- Two symlinks in `hypr/.config/hypr/wallpapers/` use absolute paths under `/home/zakkaria/Pictures/Wallpapers`. Recreate them if the user or machine ever changes:

        ln -sf ~/Pictures/Wallpapers ~/.dotfiles/hypr/.config/hypr/wallpapers/Wallpapers
        ln -sf ~/Pictures/Wallpapers/crimson-foliage.png ~/.dotfiles/hypr/.config/hypr/wallpapers/crimson-foliage.png

- `localsendd.service` and `91-kbd-backlight-sync.rules` hardcode `/home/zakkaria`.
- `config.json` silently drops unrecognised keys on save, so custom keys must not go in it.
