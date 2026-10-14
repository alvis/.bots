#!/usr/bin/env bash
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Start a single `t3 serve --tailscale-serve` if none runs. Tailscale only (T3 Connect unlinked).
unset NPM_CONFIG_PREFIX; export NVM_DIR=$HOME/.nvm; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1
command -v t3 >/dev/null || { echo "t3 missing (run install.sh t3)"; exit 0; }
pgrep -f 't3 serve' >/dev/null && exit 0
for i in $(seq 30); do tailscale status >/dev/null 2>&1 && break; sleep 2; done
# Tailscale only: keep T3 Connect exposure off (matches auth.sh)
t3 connect status 2>/dev/null | grep -q 'Exposure: enabled' && t3 connect unlink >/dev/null 2>&1
mkdir -p "$HOME/.t3"; cd "$HOME"
nohup t3 serve --tailscale-serve --log-level info >"$HOME/.t3/serve.log" 2>&1 </dev/null &
echo $! >"$HOME/.t3/serve.pid"
