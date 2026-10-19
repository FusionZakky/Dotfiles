#!/usr/bin/env bash
# Runs a theme in the real greeter's test mode. When the window is closed, brings the picker back (it restores its own place).
# usage: sddm-test.sh <theme_path>
sddm-greeter-qt6 --test-mode --theme "$1"
qs -c ii ipc call wallpaperPicker open >/dev/null 2>&1
