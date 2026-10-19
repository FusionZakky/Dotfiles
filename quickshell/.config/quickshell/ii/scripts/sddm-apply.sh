#!/usr/bin/env bash
# Run as root (the picker calls it through pkexec). Same steps as the sddm-theme fish function, plus:
#  - conflicting config files are backed up instead of just deleted
#  - a theme the sddm user can't read (e.g. inside a private home dir) is copied instead of symlinked
# usage: sddm-apply.sh <theme_name> <theme_path>
name="$1"; path="$2"
[ -n "$name" ] && [[ "$name" != */* ]] && [ -f "$path/Main.qml" ] || { echo "bad theme: '$name' ($path)" >&2; exit 2; }

target="/usr/share/sddm/themes/$name"
[ -L "$target" ] && [ ! -e "$target" ] && rm -f "$target"
if [ ! -e "$target" ]; then
    readable=1
    if id sddm >/dev/null 2>&1 && ! runuser -u sddm -- test -r "$path/Main.qml" 2>/dev/null; then readable=0; fi
    if [ "$readable" = 1 ]; then
        ln -s "$path" "$target"
    else
        cp -rL "$path" "$target"
        echo "theme is not readable by the sddm user where it lives, copied it instead of linking"
    fi
fi

backup="/etc/sddm-picker-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
for f in /etc/sddm.conf /etc/sddm.conf.d/theme.conf /etc/sddm.conf.d/virtualkbd.conf /etc/sddm.conf.d/99-theme.conf; do
    [ -e "$f" ] && cp -a "$f" "$backup/" && rm -f "$f"
done
rmdir "$backup" 2>/dev/null

mkdir -p /etc/sddm.conf.d
printf '[Theme]\nCurrent=%s\n\n[General]\nInputMethod=\n\n[Input]\nInputMethod=\n' "$name" > /etc/sddm.conf.d/zz-override.conf
echo "SDDM theme set to $name"
