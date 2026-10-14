#!/usr/bin/env bash
# First-time / selective auth for harnesses and services.
# Default: device-code logins only (codex, grok, gh, opencode), skip if already in.
# Claude has no device-code flow — only with --all or --only-claude.
# Run this yourself; install.sh never calls it.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

PATH="${HOME}/.local/bin:${HOME}/.opencode/bin:${HOME}/.grok/bin:${HOME}/.claude/bin:${PATH:-}"
export PATH
export HERMES_HOME="${HERMES_HOME:-/workspace/.hermes}"

AUTH_MODE="missing"   # missing | all | only
ONLY_SERVICES=()
RESULTS=()

SERVICES=(claude codex grok gh tailscale whatsapp t3 opencode hermes xurl)
# Default ./auth.sh only runs these (device-code / headless flows).
DEVICE_CODE_SERVICES=(codex grok gh opencode)

usage() {
  cat <<'EOF'
Usage:
  ./auth.sh                 device-code logins only (skip if already in)
  ./auth.sh --all           force re-login every service (includes Claude)
  ./auth.sh --only-NAME     force login for one service (repeatable)
  ./auth.sh --only-claude   Claude Code (no device code — TTY wizard)

Default services (device-code):
  codex      Codex CLI (codex login --device-auth)
  grok       Grok Build CLI (grok login --device-auth)
  gh         GitHub CLI + git identity  (also: --only-github)
  opencode   OpenCode: ChatGPT/Codex (openai) + Grok (xai)

Needs --all or --only-NAME (no device code):
  claude     Claude Code (claude auth login)
  tailscale  tailscale up
  whatsapp   Hermes Baileys QR (hermes whatsapp)
  t3         t3 pair --tailscale
  hermes     OPENROUTER_API_KEY into ~/.hermes/.env (if set)
  xurl       xurl OAuth (prints next step; needs app client id)

install.sh never runs this. After a reset: ./install.sh && ./auth.sh
EOF
}

is_tty() { [[ -t 0 && -t 1 ]]; }
force_mode() { [[ "$AUTH_MODE" == "all" || "$AUTH_MODE" == "only" ]]; }

is_device_code() {
  local name="$1" s
  for s in "${DEVICE_CODE_SERVICES[@]}"; do
    [[ "$s" == "$name" ]] && return 0
  done
  return 1
}

want() {
  local name="$1"
  if [[ "$AUTH_MODE" == "only" ]]; then
    local s
    for s in "${ONLY_SERVICES[@]}"; do
      [[ "$s" == "$name" ]] && return 0
    done
    return 1
  fi
  # Default: device-code only. Claude and other TTY wizards need --all / --only-*.
  if [[ "$AUTH_MODE" == "missing" ]] && ! is_device_code "$name"; then
    return 1
  fi
  return 0
}

record() { RESULTS+=("$1|$2"); }

need_tty() {
  local cmd="$1"
  if is_tty; then
    return 0
  fi
  warn "non-interactive — skip. Re-run: $cmd"
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --all) AUTH_MODE="all"; shift ;;
      --only-github) AUTH_MODE="only"; ONLY_SERVICES+=("gh"); shift ;;
      --only-*) AUTH_MODE="only"; ONLY_SERVICES+=("${1#--only-}"); shift ;;
      *) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
  if [[ "$AUTH_MODE" == "only" ]]; then
    local s known ok
    for s in "${ONLY_SERVICES[@]}"; do
      ok=0
      for known in "${SERVICES[@]}"; do
        [[ "$s" == "$known" ]] && ok=1 && break
      done
      if (( ok == 0 )); then
        echo "Unknown service: $s" >&2
        echo "Known: ${SERVICES[*]}" >&2
        exit 1
      fi
    done
  fi
}

codex_logged_in() { have codex && codex login status 2>/dev/null | grep -qiE 'logged in'; }
grok_logged_in() {
  # `grok auth` opens a TUI — never use it as a status probe.
  have grok || return 1
  python3 -c '
import json, sys
from pathlib import Path
for p in (Path("/workspace/.grok/auth.json"), Path.home()/".grok"/"auth.json"):
    if not p.exists():
        continue
    try:
        data = json.loads(p.read_text() or "{}")
    except Exception:
        continue
    if isinstance(data, dict) and data:
        sys.exit(0)
sys.exit(1)
'
}
claude_logged_in() { have claude && claude auth status 2>/dev/null | grep -qiE '"loggedIn"[[:space:]]*:[[:space:]]*true'; }
gh_logged_in() { have gh && gh auth status >/dev/null 2>&1; }
tailscale_up() { have tailscale && tailscale ip -4 >/dev/null 2>&1; }
whatsapp_paired() {
  local sess="${HERMES_HOME}/whatsapp/session"
  [[ -d "$sess" ]] && find "$sess" -type f -print -quit 2>/dev/null | grep -q .
}
xurl_logged_in() { have xurl && xurl auth status 2>/dev/null | grep -qiE 'logged in|authenticated|authorized'; }
hermes_has_openrouter() {
  local envf="${HERMES_HOME}/.env"
  [[ -f "$envf" ]] && grep -qE '^[[:space:]]*OPENROUTER_API_KEY=.+' "$envf"
}

opencode_has() {
  local id="$1"
  python3 -c '
import json, sys
from pathlib import Path
pid = sys.argv[1]
for p in (Path("/workspace/.local/share/opencode/auth.json"), Path.home()/".local/share/opencode"/"auth.json"):
    if not p.exists():
        continue
    try:
        data = json.loads(p.read_text() or "{}")
    except Exception:
        continue
    rec = data.get(pid) if isinstance(data, dict) else None
    if isinstance(rec, dict) and (rec.get("key") or rec.get("access") or rec.get("type")):
        sys.exit(0)
sys.exit(1)
' "$id"
}

auth_codex() {
  log "Codex CLI login"
  if ! have codex; then warn "codex missing — skip"; record "codex" "missing-binary"; return 0; fi
  if ! force_mode && codex_logged_in; then ok "codex already logged in"; record "codex" "skipped"; return 0; fi
  if ! need_tty "./auth.sh --only-codex"; then record "codex" "needs-tty"; return 0; fi
  if codex login --device-auth; then ok "codex logged in"; record "codex" "logged-in"
  else warn "codex login failed or cancelled"; record "codex" "failed"; fi
}

auth_grok() {
  log "Grok Build CLI login"
  if ! have grok; then warn "grok missing — skip"; record "grok" "missing-binary"; return 0; fi
  if ! force_mode && grok_logged_in; then ok "grok already logged in"; record "grok" "skipped"; return 0; fi
  if ! need_tty "./auth.sh --only-grok"; then record "grok" "needs-tty"; return 0; fi
  if grok login --device-auth; then ok "grok logged in"; record "grok" "logged-in"
  else warn "grok login failed or cancelled"; record "grok" "failed"; fi
}

auth_claude() {
  log "Claude Code login"
  if ! have claude; then warn "claude missing — skip"; record "claude" "missing-binary"; return 0; fi
  if ! force_mode && claude_logged_in; then ok "claude already logged in"; record "claude" "skipped"; return 0; fi
  if ! need_tty "./auth.sh --only-claude"; then record "claude" "needs-tty"; return 0; fi
  warn "Claude Code has no device-code login — using claude auth login"
  if claude auth login; then ok "claude logged in"; record "claude" "logged-in"
  else warn "claude auth login failed or cancelled"; record "claude" "failed"; fi
}

auth_gh() {
  log "GitHub CLI + git identity"
  if ! have gh; then warn "gh missing — skip"; record "gh" "missing-binary"; return 0; fi
  if force_mode || ! gh_logged_in; then
    if ! need_tty "./auth.sh --only-gh"; then record "gh" "needs-tty"; return 0; fi
    if ! gh auth login --hostname github.com --git-protocol https --scopes user:email,gist,read:org; then
      warn "gh auth login failed or cancelled"; record "gh" "failed"; return 0
    fi
  else
    ok "gh already authenticated"
  fi
  gh auth setup-git >/dev/null 2>&1 || warn "gh auth setup-git failed"
  local login name email id
  login="$(gh api user --jq .login 2>/dev/null || true)"
  name="$(gh api user --jq '.name // empty' 2>/dev/null || true)"
  id="$(gh api user --jq .id 2>/dev/null || true)"
  email="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
  if [[ -z "${email}" ]]; then
    email="$(gh api user/emails --jq '[.[] | select(.primary==true and .verified==true) | .email][0] // empty' 2>/dev/null || true)"
  fi
  if [[ -z "${email}" && -n "${id}" && -n "${login}" ]]; then
    email="${id}+${login}@users.noreply.github.com"
  fi
  [[ -z "${name}" ]] && name="${login}"
  if [[ -n "${login}" && -n "${name}" && -n "${email}" ]]; then
    git config --global user.name "${name}"
    git config --global user.email "${email}"
    git config --global github.user "${login}"
    ok "git identity ${name} <${email}>"
  fi
  record "gh" "logged-in"
}

auth_tailscale() {
  log "Tailscale login"
  if ! have tailscale; then warn "tailscale missing — skip"; record "tailscale" "missing-binary"; return 0; fi
  if ! force_mode && tailscale_up; then
    ok "tailscale already connected ($(tailscale ip -4 2>/dev/null || echo ok))"
    sudo tailscale set --operator="${USER}" >/dev/null 2>&1 || true
    record "tailscale" "skipped"; return 0
  fi
  if ! need_tty "./auth.sh --only-tailscale"; then record "tailscale" "needs-tty"; return 0; fi
  if sudo tailscale up --accept-routes=false --ssh --netfilter-mode=off --hostname="${TS_HOSTNAME:-x}"; then
    sudo tailscale set --ssh >/dev/null 2>&1 || true
    ok "tailscale up — IP $(tailscale ip -4 2>/dev/null || echo ?)"
    sudo tailscale set --operator="${USER}" >/dev/null 2>&1 || true
    record "tailscale" "logged-in"
  else
    warn "tailscale up failed or cancelled"; record "tailscale" "failed"
  fi
}

auth_whatsapp() {
  log "Hermes WhatsApp QR"
  if ! have hermes; then warn "hermes missing — skip"; record "whatsapp" "missing-binary"; return 0; fi
  persist_home_path "${HOME}/.hermes" "/workspace/.hermes"
  export HERMES_HOME="/workspace/.hermes"
  if ! force_mode && whatsapp_paired; then ok "WhatsApp session already present"; record "whatsapp" "skipped"; return 0; fi
  if ! need_tty "./auth.sh --only-whatsapp"; then record "whatsapp" "needs-tty"; return 0; fi
  warn "Phone: WhatsApp → Linked Devices → Link a Device → scan QR"
  if hermes whatsapp; then
    ok "WhatsApp pairing finished"
    chmod 700 "${HERMES_HOME}/whatsapp/session" 2>/dev/null || true
    record "whatsapp" "logged-in"
  else
    warn "hermes whatsapp failed or cancelled"; record "whatsapp" "failed"
  fi
}

auth_t3() {
  log "T3 pair over Tailscale"
  if ! have t3; then warn "t3 missing — skip"; record "t3" "missing-binary"; return 0; fi
  if ! have tailscale || ! tailscale_up; then
    warn "tailscale not connected — skip T3 pair"; record "t3" "needs-tailscale"; return 0
  fi
  if ! need_tty "./auth.sh --only-t3"; then record "t3" "needs-tty"; return 0; fi
  t3 connect unlink >/dev/null 2>&1 || true
  sudo tailscale set --operator="${USER}" >/dev/null 2>&1 || true
  mkdir -p "${HOME}/.t3"
  if ! pgrep -f 't3 serve' >/dev/null 2>&1; then
    nohup t3 serve --tailscale-serve --log-level info >"${HOME}/.t3/serve.log" 2>&1 &
    echo $! >"${HOME}/.t3/serve.pid"
    local i
    for i in $(seq 1 15); do
      grep -q "server is ready" "${HOME}/.t3/serve.log" 2>/dev/null && break
      sleep 1
    done
  fi
  if ! pgrep -f "t3 serve" >/dev/null 2>&1; then
    warn "t3 serve not running"; record "t3" "failed"; return 0
  fi
  if t3 pair --tailscale; then ok "t3 pair --tailscale completed"; record "t3" "logged-in"
  else warn "t3 pair --tailscale failed"; record "t3" "failed"; fi
}

# OpenCode: ChatGPT/Codex (provider openai) + Grok (provider xai)
opencode_try_login() {
  local provider="$1"
  shift
  local method
  for method in "$@"; do
    log "opencode auth login -p ${provider} -m ${method}"
    if opencode auth login -p "$provider" -m "$method"; then
      ok "OpenCode ${provider} via ${method}"
      return 0
    fi
    warn "method failed: ${method}"
  done
  if opencode auth login -p "$provider"; then
    ok "OpenCode ${provider} (method picker)"
    return 0
  fi
  return 1
}

auth_opencode() {
  log "OpenCode providers — Codex (ChatGPT) + Grok (xAI)"
  if ! have opencode; then warn "opencode missing — skip"; record "opencode" "missing-binary"; return 0; fi
  persist_home_path "${HOME}/.local/share/opencode" "/workspace/.local/share/opencode"
  persist_home_path "${HOME}/.config/opencode" "/workspace/.config/opencode"

  local did=0 fail=0 needtty=0

  if force_mode || ! opencode_has openai; then
    if need_tty "./auth.sh --only-opencode"; then
      if opencode_try_login openai \
        "ChatGPT Plus/Pro (headless)" \
        "ChatGPT Pro/Plus (headless)" \
        "ChatGPT Plus/Pro" \
        "device-code"; then
        did=1
      else
        warn "OpenCode openai/codex login failed"; fail=1
      fi
    else
      record "opencode-openai" "needs-tty"
      needtty=1
    fi
  else
    ok "OpenCode already has openai/codex credentials"
  fi

  if force_mode || ! opencode_has xai; then
    if need_tty "./auth.sh --only-opencode"; then
      if opencode_try_login xai \
        "SuperGrok Subscription" \
        "xAI Grok OAuth (Headless / Remote / VPS)" \
        "Headless / Remote / VPS"; then
        did=1
      else
        warn "OpenCode xai/grok login failed"; fail=1
      fi
    else
      record "opencode-xai" "needs-tty"
      needtty=1
    fi
  else
    ok "OpenCode already has xai/grok credentials"
  fi

  if (( fail )); then record "opencode" "failed"
  elif (( did )); then record "opencode" "logged-in"
  elif (( needtty )); then record "opencode" "needs-tty"
  else record "opencode" "skipped"
  fi
}

auth_hermes() {
  log "Hermes OpenRouter key"
  persist_home_path "${HOME}/.hermes" "/workspace/.hermes"
  export HERMES_HOME="/workspace/.hermes"
  mkdir -p "$HERMES_HOME"
  local envf="${HERMES_HOME}/.env"
  touch "$envf"
  chmod 600 "$envf" 2>/dev/null || true

  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    if hermes_has_openrouter && ! force_mode; then
      ok "Hermes already has OPENROUTER_API_KEY"; record "hermes" "skipped"
    else
      warn "OPENROUTER_API_KEY unset — Hermes OpenRouter not written"; record "hermes" "needs-key"
    fi
    return 0
  fi
  if hermes_has_openrouter && ! force_mode; then
    ok "Hermes already has OPENROUTER_API_KEY"; record "hermes" "skipped"; return 0
  fi
  python3 -c '
import os, re
from pathlib import Path
p = Path("'"$envf"'")
key = os.environ["OPENROUTER_API_KEY"]
text = p.read_text() if p.exists() else ""
text2, n = re.subn(r"(?m)^([ \t]*OPENROUTER_API_KEY=).*$", r"\1" + key, text, count=1)
if not n:
    text2 = text.rstrip() + ("\n" if text and not text.endswith("\n") else "") + "OPENROUTER_API_KEY=" + key + "\n"
p.write_text(text2)
p.chmod(0o600)
'
  ok "OPENROUTER_API_KEY written to ${envf}"
  record "hermes" "logged-in"
}

auth_xurl() {
  log "xurl auth"
  if ! have xurl; then warn "xurl missing — skip"; record "xurl" "missing-binary"; return 0; fi
  if ! force_mode && xurl_logged_in; then ok "xurl already authenticated"; record "xurl" "skipped"; return 0; fi
  warn "xurl needs an app client id/secret — not stored here"
  warn "Then: xurl auth apps add my-app --client-id ID --client-secret SECRET"
  warn "      xurl auth oauth2 --app my-app"
  record "xurl" "needs-app"
}

print_status() {
  log "Auth status"
  printf '%-18s %s\n' "SERVICE" "RESULT"
  local row name st
  for row in "${RESULTS[@]}"; do
    name="${row%%|*}"
    st="${row#*|}"
    printf '%-18s %s\n' "$name" "$st"
  done
}

main() {
  parse_args "$@"
  local svc
  for svc in "${SERVICES[@]}"; do
    want "$svc" || continue
    "auth_${svc}"
  done
  if [[ "$AUTH_MODE" == "missing" ]]; then
    log "Skipped (no device-code — ./auth.sh --all or --only-NAME)"
    for svc in "${SERVICES[@]}"; do
      is_device_code "$svc" && continue
      printf '    %s\n' "$svc"
    done
  fi
  print_status
}

main "$@"
