#!/usr/bin/env bash
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Restarts tailscaled if the node reports offline for ~2 minutes (box proxy can kill control long-polls).
set -u
LOG=/workspace/.tailscale/watchdog.log
exec 9>/tmp/tailscale-watchdog.lock; flock -n 9 || exit 0
bad=0
while true; do
  if [ "$(tailscale status --json 2>/dev/null | jq -r '.Self.Online' 2>/dev/null)" = "true" ]; then bad=0; else bad=$((bad+1)); fi
  if [ "$bad" -ge 4 ]; then
    echo "$(date '+%F %T') offline, restarting tailscaled" >>"$LOG"
    sudo pkill -x tailscaled; sleep 2; bash "$HERE"/tailscale-ensure.sh >>"$LOG" 2>&1; bad=0
  fi
  sleep 30
done
