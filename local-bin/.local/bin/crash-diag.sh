#!/bin/bash
# crash-diag.sh — run this AFTER a Hyprland/system freeze + power-cycle,
# as soon as you're back at a terminal. Gathers everything needed to
# diagnose the crash in one shot. Output goes to ~/crash-logs/<timestamp>/

set -uo pipefail

OUTDIR="$HOME/crash-logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

echo "Collecting crash diagnostics into $OUTDIR ..."

# 1. Previous boot's full log (the crashed session)
journalctl -b -1 --no-pager > "$OUTDIR/full-journal-prev-boot.log" 2>&1

# 2. Previous boot, errors only (quick triage)
journalctl -b -1 -p err --no-pager > "$OUTDIR/errors-prev-boot.log" 2>&1

# 3. Kernel ring buffer, previous boot (GPU hangs, oops, panics live here)
journalctl -k -b -1 --no-pager > "$OUTDIR/kernel-prev-boot.log" 2>&1

# 4. OOM / GPU hang / reset quick-grep summary
{
  echo "--- OOM / killed process matches ---"
  journalctl -b -1 --no-pager | grep -iE "oom|out of memory|killed process"
  echo
  echo "--- i915 / GPU hang / reset / hangcheck matches ---"
  journalctl -k -b -1 --no-pager | grep -iE "gpu hang|hangcheck|\breset\b|fence timeout"
} > "$OUTDIR/quick-signals.log" 2>&1

# 5. Any coredumps generated (most recent 20)
coredumpctl list --no-legend --no-pager 2>&1 | tail -20 > "$OUTDIR/coredumps-list.log"

# 6. udev worker issues in the previous boot
journalctl -b -1 -u systemd-udevd --no-pager > "$OUTDIR/udev-prev-boot.log" 2>&1

# 7. hypridle / hyprsunset process + config state (current boot, for comparison)
{
  echo "--- ps: hyprsunset / hypridle / Hyprland ---"
  ps aux | grep -iE "hyprsunset|hypridle|Hyprland" | grep -v grep
  echo
  echo "--- hypridle.conf ---"
  cat ~/.config/hypr/hypridle.conf 2>&1
  echo
  echo "--- hyprsunset version ---"
  hyprsunset --version 2>&1
} > "$OUTDIR/hypr-state.log" 2>&1

# 8. Try to grab the crashed session's Hyprland log before it's gone.
# NOTE: this only works if you run this script WITHOUT rebooting again
# after the crash — /run is tmpfs and wipes on every reboot.
HYPR_LOG=$(find /run/user/1000/hypr -maxdepth 2 -iname "*.log" 2>/dev/null | head -1)
if [ -n "$HYPR_LOG" ]; then
  cp "$HYPR_LOG" "$OUTDIR/hyprland-current-session.log"
  echo "Copied live Hyprland log: $HYPR_LOG"
else
  echo "No live Hyprland log found in /run (expected if you've already rebooted since the crash)."
fi

# 9. Bundle everything into one file for easy pasting/sharing
{
  echo "======================================================"
  echo " CRASH DIAGNOSTIC BUNDLE - $(date)"
  echo "======================================================"
  for f in "$OUTDIR"/*.log; do
    echo
    echo "───── $(basename "$f") ─────"
    cat "$f"
  done
} > "$OUTDIR/SUMMARY.txt"

echo ""
echo "Done. Full bundle: $OUTDIR/SUMMARY.txt"
echo "Paste that file's contents (or the individual .log files) back to Claude next session."
