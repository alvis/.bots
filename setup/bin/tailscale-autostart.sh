#!/usr/bin/env bash
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Shell-start hook: ensure tailscaled (persistent state) then t3 serve. Fast no-op when both run.
# Opt out: touch /workspace/.tailscale/autostart.disabled (all) or ~/.t3/autostart.disabled (t3 only).
[ -f /workspace/.tailscale/autostart.disabled ] && exit 0
need_t3=1; [ -f "$HOME/.t3/autostart.disabled" ] && need_t3=0
pgrep -f 't3 serve' >/dev/null 2>&1 && need_t3=0
pgrep -x tailscaled >/dev/null 2>&1 && [ $need_t3 = 0 ] && exit 0
exec 9>/tmp/tailscale-autostart.lock; flock -n 9 || exit 0
mkdir -p /workspace/.tailscale
( "$HERE"/tailscale-ensure.sh; [ $need_t3 = 1 ] && "$HERE"/t3-serve-ensure.sh ) </dev/null >>/workspace/.tailscale/autostart.log 2>&1 9>&- &
disown 2>/dev/null; exit 0
