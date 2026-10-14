#!/usr/bin/env bash
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# Idempotent: install tailscale static binary if missing, start tailscaled with persistent state.
set -u
STATE_DIR=/workspace/.tailscale; SOCK=/var/run/tailscale/tailscaled.sock
LOG=$STATE_DIR/tailscaled.log
# Machine name used by T3 and others: keep it "x" (rebuild resets it)
[ "$(hostname)" = "${TS_HOSTNAME:-x}" ] || { sudo hostname "${TS_HOSTNAME:-x}"; grep -q " ${TS_HOSTNAME:-x}$" /etc/hosts || echo "127.0.1.1 ${TS_HOSTNAME:-x}" | sudo tee -a /etc/hosts >/dev/null; }
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
if ! command -v tailscale >/dev/null || ! command -v tailscaled >/dev/null; then
  ver="$(curl -fsSL "https://pkgs.tailscale.com/stable/?mode=json" | tr -d '\n\t ' | sed -n 's/.*"TarballsVersion":"\([^"]*\)".*/\1/p')"
  [ -n "$ver" ] || { echo "cannot resolve tailscale version" >&2; exit 1; }
  curl -fsSL -o /tmp/ts.tgz "https://pkgs.tailscale.com/stable/tailscale_${ver}_amd64.tgz" && tar -xzf /tmp/ts.tgz -C /tmp &&
  sudo install -m755 /tmp/tailscale_${ver}_amd64/tailscale /tmp/tailscale_${ver}_amd64/tailscaled /usr/local/bin/ || exit 1
  hash -r
fi
if ! pgrep -x tailscaled >/dev/null; then
  sudo mkdir -p /var/run/tailscale
  TUN=(); [ -c /dev/net/tun ] || TUN=(--tun=userspace-networking)
  sudo nohup tailscaled --state="$STATE_DIR/tailscaled.state" --statedir="$STATE_DIR" --socket="$SOCK" --port=41641 "${TUN[@]}" </dev/null >>"$LOG" 2>&1 &
  for i in $(seq 20); do [ -S "$SOCK" ] && break; sleep 0.5; done
fi
# Accept inbound access: enable Tailscale SSH once logged in (idempotent)
for i in $(seq 20); do tailscale ip -4 >/dev/null 2>&1 && { sudo tailscale set --ssh --netfilter-mode=off >/dev/null 2>&1 || true; break; }; sleep 1; done
# Keep it online: start watchdog once
pgrep -f tailscale-watchdog.sh >/dev/null || nohup bash "$HERE"/tailscale-watchdog.sh </dev/null >/dev/null 2>&1 &
exit 0
