#!/usr/bin/env bash
# Install Node 26, then T3 Code, Claude Code, Codex, Grok Build,
# OpenCode, Hermes Agent (incl. WhatsApp gateway), xurl (X API CLI), and register
# alvis/.agents as a plugin marketplace on those harnesses.
# OpenCode + Hermes default model: OpenRouter z-ai/glm-5.3-flash via Cloudflare.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

readonly MARKETPLACE="alvis/.agents"
readonly CLAUDE_SCOPE="user"
readonly AGENTS_CLONE_DIR="/workspace/alvis/.agents"
readonly NVM_INSTALL_TAG="v0.40.7"
readonly NODE_MAJOR="26"
NVM_DIR="${HOME}/.nvm"


load_nvm() {
  # shellcheck disable=SC1091
  [[ -s "${NVM_DIR}/nvm.sh" ]] && . "${NVM_DIR}/nvm.sh"
}

install_node() {
  log "Installing Node.js ${NODE_MAJOR} via nvm"
  need_cmd curl

  # nvm refuses to run when a global npm prefix is forced
  unset NPM_CONFIG_PREFIX
  export NVM_DIR

  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_TAG}/install.sh" | bash
  else
    ok "nvm already installed"
  fi

  load_nvm
  if ! type nvm >/dev/null 2>&1; then
    echo "nvm failed to load from ${NVM_DIR}/nvm.sh" >&2
    exit 1
  fi

  nvm install "${NODE_MAJOR}"
  nvm alias default "${NODE_MAJOR}"
  nvm use "${NODE_MAJOR}"

  # Prefer nvm's node over any system node for the rest of this script
  hash -r 2>/dev/null || true
  ok "node $(node -v) at $(command -v node) (npm $(npm -v))"

  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [[ "$major" != "$NODE_MAJOR" ]]; then
    echo "Expected Node ${NODE_MAJOR}, got $(node -v) from $(command -v node)" >&2
    exit 1
  fi
}

PATH="${HOME}/.local/bin:${HOME}/.opencode/bin:${HOME}/.grok/bin:${HOME}/.claude/bin:${PATH:-}"
export PATH

install_claude() {
  log "Installing Claude Code"
  if have claude; then
    ok "already present: $(claude --version 2>/dev/null | head -n1 || echo claude)"
    return 0
  fi
  if have brew; then
    brew install --cask claude-code
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  hash -r 2>/dev/null || true
  # Claude native installer often drops into ~/.local/bin
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
  if have claude; then
    ok "claude $(claude --version 2>/dev/null | head -n1 || true)"
  else
    warn "claude not on PATH yet — open a new shell or add the install dir to PATH"
  fi
}

install_codex() {
  log "Installing Codex CLI"
  if have codex; then
    ok "already present: $(codex --version 2>/dev/null | head -n1 || echo codex)"
    return 0
  fi
  if have brew; then
    brew install --cask codex || curl -fsSL https://chatgpt.com/codex/install.sh | sh
  else
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
  fi
  hash -r 2>/dev/null || true
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
  if have codex; then
    ok "codex $(codex --version 2>/dev/null | head -n1 || true)"
  else
    warn "codex not on PATH yet — open a new shell after install"
  fi
}

install_grok() {
  log "Installing Grok Build CLI"
  if have grok; then
    ok "already present: $(grok --version 2>/dev/null | head -n1 || echo grok)"
    return 0
  fi
  curl -fsSL https://x.ai/cli/install.sh | bash
  PATH="${HOME}/.grok/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true
  if have grok; then
    ok "grok $(grok --version 2>/dev/null | head -n1 || true)"
  else
    warn "grok not on PATH yet — ensure ${HOME}/.grok/bin is on PATH"
  fi
}

install_hermes() {
  log "Installing Hermes Agent (latest)"
  need_cmd curl
  need_cmd git

  # Durable home under /workspace (WhatsApp Baileys session, .env, checkout)
  local ws_hermes="/workspace/.hermes"
  persist_home_path "${HOME}/.hermes" "${ws_hermes}"
  export HERMES_HOME="${ws_hermes}"

  # Installer downloads Node as .tar.xz on Linux
  if [[ "$os" == "Linux" ]] && ! have xz; then
    if have apt-get; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq xz-utils
    elif have dnf; then
      sudo dnf install -y xz
    elif have yum; then
      sudo yum install -y xz
    else
      warn "xz/xz-utils recommended for Hermes Node download"
    fi
  fi

  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true

  if have hermes; then
    ok "already present: $(hermes --version 2>/dev/null | head -n1 || echo hermes)"
    # Do not run `hermes update` here — it prompts and can hang a reset install.
  else
    # --skip-setup: packages only; auth/config is auth.sh
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup
    PATH="${HOME}/.local/bin:${PATH}"
    export PATH
    hash -r 2>/dev/null || true
  fi

  if have hermes; then
    ok "hermes $(hermes --version 2>/dev/null | head -n1 || true) (HERMES_HOME=${HERMES_HOME:-/workspace/.hermes})"
  else
    warn "hermes not on PATH yet — ensure ${HOME}/.local/bin is on PATH (and reopen the shell)"
  fi
}


install_xurl() {
  log "Installing xurl (official X API CLI)"
  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true

  if have xurl; then
    ok "already present: $(xurl --version 2>/dev/null | head -n1 || echo xurl)"
    return 0
  fi

  need_cmd curl
  if have brew; then
    brew install --cask xdevplatform/tap/xurl || \
      curl -fsSL https://raw.githubusercontent.com/xdevplatform/xurl/main/install.sh | bash
  elif have npm; then
    # Prefer official shell installer on Linux (no sudo); npm as fallback
    if ! curl -fsSL https://raw.githubusercontent.com/xdevplatform/xurl/main/install.sh | bash; then
      warn "xurl install.sh failed — trying npm global"
      npm install -g @xdevplatform/xurl || warn "npm xurl install failed"
    fi
  else
    curl -fsSL https://raw.githubusercontent.com/xdevplatform/xurl/main/install.sh | bash
  fi

  PATH="${HOME}/.local/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true
  if have xurl; then
    ok "xurl $(xurl --version 2>/dev/null | head -n1 || true)"
  else
    warn "xurl not on PATH yet — ensure ${HOME}/.local/bin is on PATH"
  fi
}


# Seed WhatsApp (Baileys) config + gateway. QR pairing is in auth.sh.
setup_hermes_whatsapp() {
  log "Hermes WhatsApp (Baileys bridge) setup"
  if ! have hermes; then
    warn "hermes missing — skip WhatsApp"
    return 0
  fi

  persist_home_path "${HOME}/.hermes" "/workspace/.hermes"
  export HERMES_HOME="/workspace/.hermes"
  local hermes_home="${HERMES_HOME}"
  mkdir -p "${hermes_home}/whatsapp"
  chmod 700 "${hermes_home}/whatsapp" 2>/dev/null || true

  local envf="${hermes_home}/.env"
  touch "$envf"
  chmod 600 "$envf" 2>/dev/null || true

  ensure_env_kv() {
    local key="$1" val="$2"
    if grep -qE "^[[:space:]]*${key}=" "$envf" 2>/dev/null; then
      ok ".env already has ${key}"
    else
      printf '%s=%s\n' "$key" "$val" >> "$envf"
      ok "wrote ${key} to ${envf}"
    fi
  }

  ensure_env_kv "WHATSAPP_ENABLED" "true"
  ensure_env_kv "WHATSAPP_MODE" "bot"

  if grep -qE '^[[:space:]]*WHATSAPP_ALLOWED_USERS=[[:space:]]*$' "$envf" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -F= '
      $1 ~ /^[[:space:]]*WHATSAPP_ALLOWED_USERS$/ { print "WHATSAPP_ALLOWED_USERS=447717354944"; next }
      { print }
    ' "$envf" > "$tmp"
    cat "$tmp" > "$envf"
    rm -f "$tmp"
    ok "filled empty WHATSAPP_ALLOWED_USERS=447717354944"
  elif grep -qE '^[[:space:]]*WHATSAPP_ALLOWED_USERS=' "$envf" 2>/dev/null; then
    if ! grep -qE '^[[:space:]]*WHATSAPP_ALLOWED_USERS=.*447717354944' "$envf" 2>/dev/null; then
      local tmp
      tmp="$(mktemp)"
      awk -F= '
        $1 ~ /^[[:space:]]*WHATSAPP_ALLOWED_USERS$/ {
          v=$2
          if (v !~ /447717354944/) {
            if (v == "" || v == "*") print "WHATSAPP_ALLOWED_USERS=447717354944"
            else print "WHATSAPP_ALLOWED_USERS=" v ",447717354944"
          } else print $0
          next
        }
        { print }
      ' "$envf" > "$tmp"
      cat "$tmp" > "$envf"
      rm -f "$tmp"
      ok "ensured 447717354944 is in WHATSAPP_ALLOWED_USERS"
    else
      ok "447717354944 already in WHATSAPP_ALLOWED_USERS"
    fi
  fi
  if ! grep -qE '^[[:space:]]*WHATSAPP_ALLOWED_USERS=' "$envf" 2>/dev/null \
     && ! grep -qE '^[[:space:]]*WHATSAPP_ALLOW_ALL_USERS=' "$envf" 2>/dev/null; then
    {
      echo '# Comma-separated phones with country code, no +'
      echo 'WHATSAPP_ALLOWED_USERS=447717354944'
    } >> "$envf"
    ok "seeded WHATSAPP_ALLOWED_USERS=447717354944 in ${envf}"
  else
    ok "WhatsApp allowlist already configured in .env"
  fi

  local cfg="${hermes_home}/config.yaml"
  if [[ ! -f "$cfg" ]]; then
    cat > "$cfg" <<'YAML'
# Hermes Agent config (seeded by install.sh)
unauthorized_dm_behavior: pair
whatsapp:
  unauthorized_dm_behavior: ignore
  send_read_receipts: false
YAML
    ok "seeded ${cfg}"
  elif ! grep -qE '^[[:space:]]*whatsapp:' "$cfg" 2>/dev/null; then
    cat >> "$cfg" <<'YAML'

# --- WhatsApp (seeded by install.sh) ---
whatsapp:
  unauthorized_dm_behavior: ignore
  send_read_receipts: false
YAML
    ok "appended whatsapp block to ${cfg}"
  else
    ok "config.yaml already has a whatsapp section"
  fi

  # QR pairing: ./auth.sh --only-whatsapp

  # No systemd here: `gateway start` runs in the foreground and would hang setup.
  if timeout 15 hermes gateway install >/dev/null 2>&1; then
    ok "hermes gateway unit installed (start later: hermes gateway run)"
  else
    warn "hermes gateway install skipped — start later: hermes gateway run"
  fi

  ok "WhatsApp session dir: ${hermes_home}/whatsapp/session"
}

install_t3() {
  log "Installing T3 Code (CLI only — no desktop GUI)"
  ensure_build_tools || warn "continuing without a full toolchain; t3 native deps may fail"

  if have npm; then
    if ! npm install -g --allow-scripts=msgpackr-extract,node-pty t3@latest; then
      warn "npm install -g t3@latest failed; falling back to npx-only usage"
    else
      ok "npm global t3 installed (CLI: t3 serve / t3 connect)"
    fi
  else
    warn "npm missing — skip global t3; use: npx t3@latest"
  fi

  # Intentionally no desktop app / brew cask — headless CLI only
  ok "desktop GUI skipped; use: t3 serve"
}

ensure_build_tools() {
  log "Ensuring native build tools (needed by T3 / node-pty)"
  if have make && have g++; then
    ok "make and g++ present"
    return 0
  fi
  if [[ "$os" == "Linux" ]]; then
    if have apt-get; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq build-essential
    elif have dnf; then
      sudo dnf install -y gcc-c++ make
    elif have yum; then
      sudo yum install -y gcc-c++ make
    else
      warn "Install a C/C++ toolchain (make, g++) then re-run"
      return 1
    fi
  elif [[ "$os" == "Darwin" ]]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      warn "Install Xcode Command Line Tools: xcode-select --install"
      return 1
    fi
  fi
  if have make && have g++; then
    ok "make and g++ ready"
  else
    warn "make/g++ still missing after install attempt"
    return 1
  fi
}
install_opencode() {
  log "Installing OpenCode CLI"
  need_cmd curl

  persist_home_path "${HOME}/.config/opencode" "/workspace/.config/opencode"
  persist_home_path "${HOME}/.local/share/opencode" "/workspace/.local/share/opencode"
  mkdir -p "${HOME}/.opencode/bin" "${HOME}/.local/bin"
  PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true

  if have opencode; then
    ok "already present: $(opencode --version 2>/dev/null | head -n1 || echo opencode)"
    setup_opencode_openrouter_glm
    return 0
  fi

  # 1) official installer (often fails here: no version info)
  if curl -fsSL https://opencode.ai/install | bash; then
    PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${PATH}"
    export PATH
    hash -r 2>/dev/null || true
  fi

  # 2) GitHub linux tarball (works without npm)
  if ! have opencode; then
    local tag arch asset tmp
    arch="$(uname -m)"
    case "$arch" in
      x86_64|amd64) asset="opencode-linux-x64.tar.gz" ;;
      aarch64|arm64) asset="opencode-linux-arm64.tar.gz" ;;
      *) asset="opencode-linux-x64.tar.gz" ;;
    esac
    if have gh; then
      tag="$(gh api repos/anomalyco/opencode/releases/latest --jq .tag_name 2>/dev/null || true)"
    fi
    [[ -z "${tag:-}" ]] && tag="latest"
    tmp="$(mktemp -d)"
    if have gh && [[ "$tag" != latest ]]; then
      if gh release download "$tag" --repo anomalyco/opencode --pattern "$asset" --dir "$tmp" --clobber; then
        tar -xzf "${tmp}/${asset}" -C "$tmp"
        if [[ -f "${tmp}/opencode" ]]; then
          install -m 0755 "${tmp}/opencode" "${HOME}/.opencode/bin/opencode"
          ok "opencode ${tag} from GitHub release"
        fi
      fi
    fi
    if ! have opencode; then
      warn "GitHub tarball install failed or skipped"
    fi
    rm -rf "$tmp"
  fi

  # 3) npm last (needs a real node, not a circular shim)
  if ! have opencode && have npm && have node; then
    npm install -g --allow-scripts=opencode-ai opencode-ai@latest \
      && ok "npm global opencode-ai installed" \
      || warn "npm install opencode-ai failed"
  fi

  PATH="${HOME}/.opencode/bin:${HOME}/.local/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true

  if have opencode; then
    local dest="${HOME}/.local/bin/opencode" src
    src="$(command -v opencode)"
    if [[ -n "$src" && "$src" != "$dest" ]]; then
      ln -sfn "$src" "$dest"
    fi
    ok "opencode $(opencode --version 2>/dev/null | head -n1 || true)"
  else
    warn "opencode not on PATH yet — ensure ${HOME}/.opencode/bin is on PATH"
  fi

  setup_opencode_openrouter_glm
}
setup_opencode_openrouter_glm() {
  log "Configuring OpenCode → OpenRouter glm-5.3-flash (Cloudflare only)"
  local cfg_dir="/workspace/.config/opencode"
  mkdir -p "$cfg_dir"
  persist_home_path "${HOME}/.config/opencode" "$cfg_dir"

  local cfg="${cfg_dir}/opencode.json"
  cat > "$cfg" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openrouter/z-ai/glm-5.3-flash",
  "provider": {
    "openrouter": {
      "models": {
        "z-ai/glm-5.3-flash": {
          "options": {
            "provider": {
              "only": ["cloudflare"],
              "allow_fallbacks": false
            }
          }
        }
      }
    }
  }
}
JSON
  ok "wrote ${cfg}"
  # ChatGPT/Codex + xAI/Grok OAuth: ./auth.sh --only-opencode
}

setup_hermes_openrouter_glm() {
  log "Configuring Hermes → OpenRouter glm-5.3-flash (Cloudflare only)"
  local hermes_home="/workspace/.hermes"
  persist_home_path "${HOME}/.hermes" "$hermes_home"
  export HERMES_HOME="$hermes_home"
  mkdir -p "$hermes_home"

  local cfg="${hermes_home}/config.yaml"
  if [[ ! -f "$cfg" ]]; then
    cat > "$cfg" <<'YAML'
model:
  default: z-ai/glm-5.3-flash
  provider: openrouter

provider_routing:
  only:
    - cloudflare

agent:
  reasoning_effort: high
YAML
    ok "seeded ${cfg}"
  else
    python3 - "$cfg" <<'PY'
from pathlib import Path
import re
import sys
cfg = Path(sys.argv[1])
text = cfg.read_text()

def repl_model_block(m):
    block = m.group(0)
    if re.search(r'(?m)^\s*default:', block):
        block = re.sub(r'(?m)^(\s*default:\s*).*$', r'\1z-ai/glm-5.3-flash', block, count=1)
    else:
        block = block.rstrip() + '\n  default: z-ai/glm-5.3-flash\n'
    if re.search(r'(?m)^\s*provider:', block):
        block = re.sub(r'(?m)^(\s*provider:\s*).*$', r'\1openrouter', block, count=1)
    else:
        block = block.rstrip() + '\n  provider: openrouter\n'
    if not block.endswith('\n'):
        block += '\n'
    return block

if re.search(r'(?m)^model:\s*$', text):
    text2, n = re.subn(r'(?ms)^model:\n(?:  .*\n)*', repl_model_block, text, count=1)
    text = text2 if n else text
else:
    text = 'model:\n  default: z-ai/glm-5.3-flash\n  provider: openrouter\n\n' + text

if re.search(r'(?m)^provider_routing:\s*$', text):
    text = re.sub(
        r'(?ms)^provider_routing:\n(?:  .*\n)*',
        'provider_routing:\n  only:\n    - cloudflare\n',
        text,
        count=1,
    )
else:
    text = text.rstrip() + '\n\nprovider_routing:\n  only:\n    - cloudflare\n'

if re.search(r'(?m)^agent:\s*$', text):
    if re.search(r'(?m)^\s*reasoning_effort:', text):
        text = re.sub(r'(?m)^(\s*reasoning_effort:\s*).*$', r'\1high', text, count=1)
    else:
        text = re.sub(r'(?m)^agent:\s*$', 'agent:\n  reasoning_effort: high', text, count=1)
elif not re.search(r'(?m)^agent:', text):
    text = text.rstrip() + '\n\nagent:\n  reasoning_effort: high\n'

cfg.write_text(text)
print(f'updated {cfg}')
PY
    ok "updated ${cfg} model + Cloudflare routing"
  fi

  # OPENROUTER_API_KEY write: ./auth.sh (auth_hermes)
}


ensure_marketplace_clone() {
  log "Syncing ${MARKETPLACE} checkout → ${AGENTS_CLONE_DIR}"
  local old_clone="${HOME}/.local/share/alvis-agents"

  # One-time migrate from the previous checkout location
  if [[ ! -d "${AGENTS_CLONE_DIR}/.git" && -d "${old_clone}/.git" ]]; then
    mkdir -p "$(dirname "${AGENTS_CLONE_DIR}")"
    mv "${old_clone}" "${AGENTS_CLONE_DIR}"
    ok "moved checkout from ${old_clone}"
  fi

  if [[ -d "${AGENTS_CLONE_DIR}/.git" ]]; then
    git -C "${AGENTS_CLONE_DIR}" fetch --quiet origin
    git -C "${AGENTS_CLONE_DIR}" pull --ff-only --quiet || \
      warn "pull failed; using existing checkout"
  else
    mkdir -p "$(dirname "${AGENTS_CLONE_DIR}")"
    git clone --depth 1 "https://github.com/${MARKETPLACE}.git" "${AGENTS_CLONE_DIR}"
  fi
  ok "checkout ready"
}

setup_claude_marketplace() {
  log "Claude Code: marketplace + plugins"
  if ! have claude; then
    warn "claude missing — skip marketplace"
    return 0
  fi
  ensure_marketplace_clone
  # Prefer the local checkout so installed paths stay under /workspace/alvis/.agents
  claude plugin marketplace remove alvis --scope "${CLAUDE_SCOPE}" >/dev/null 2>&1 || true
  claude plugin marketplace add "${AGENTS_CLONE_DIR}" --scope "${CLAUDE_SCOPE}" || \
    warn "marketplace add returned non-zero (may already exist)"
  claude plugin install "specification@alvis" --scope "${CLAUDE_SCOPE}" || \
    warn "claude plugin install specification failed"
  ok "Claude marketplace configured (scope=${CLAUDE_SCOPE}, source=${AGENTS_CLONE_DIR})"
  # Auth: ./auth.sh
}

setup_codex_marketplace() {
  log "Codex: marketplace + plugins"
  if ! have codex; then
    warn "codex missing — skip marketplace"
    return 0
  fi
  ensure_marketplace_clone
  codex plugin marketplace remove alvis >/dev/null 2>&1 || true
  codex plugin marketplace add "${AGENTS_CLONE_DIR}" || \
    warn "marketplace add returned non-zero (may already exist)"
  for plugin in essential coding specification; do
    codex plugin add "${plugin}@alvis" || \
      warn "codex plugin add ${plugin}@alvis failed"
  done
  ok "Codex marketplace configured (source=${AGENTS_CLONE_DIR})"
  # Auth: ./auth.sh
}

setup_grok_marketplace() {
  log "Grok Build: marketplace + plugins"
  if ! have grok; then
    warn "grok missing — skip marketplace"
    return 0
  fi
  ensure_marketplace_clone

  # Drop GitHub shorthand / old local sources so installs resolve from AGENTS_CLONE_DIR
  grok plugin marketplace remove "${MARKETPLACE}" >/dev/null 2>&1 || true
  grok plugin marketplace remove "https://github.com/${MARKETPLACE}.git" >/dev/null 2>&1 || true
  grok plugin marketplace remove "${HOME}/.local/share/alvis-agents" >/dev/null 2>&1 || true

  if out="$(grok plugin marketplace add "${AGENTS_CLONE_DIR}" 2>&1)"; then
    ok "marketplace added (${AGENTS_CLONE_DIR})"
  elif grep -qiE 'already (configured|added|exists)|already on' <<<"$out"; then
    ok "marketplace already configured"
  else
    printf '%s\n' "$out" >&2
    warn "grok marketplace add failed"
  fi

  for plugin in essential coding specification; do
    # Reinstall from the new absolute path when an older install is present
    grok plugin uninstall "${plugin}" --confirm >/dev/null 2>&1 || true
    src="${AGENTS_CLONE_DIR}/plugins/${plugin}"
    if out="$(grok plugin install "${src}" --trust 2>&1)"; then
      ok "installed ${plugin} from ${src}"
    elif grep -qiE 'already installed|already exists' <<<"$out"; then
      ok "${plugin} already installed"
    else
      printf '%s\n' "$out" >&2
      warn "grok plugin install ${plugin} failed"
    fi
  done
  ok "Grok marketplace configured (source=${AGENTS_CLONE_DIR})"
  # Auth: ./auth.sh
}



ensure_bun() {
  PATH="${HOME}/.bun/bin:${PATH:-}"
  export PATH
  if have bun; then
    ok "bun $(bun --version 2>/dev/null || echo ok)"
    return 0
  fi
  log "Installing bun (OpenCode marketplace projector)"
  curl -fsSL https://bun.sh/install | bash
  PATH="${HOME}/.bun/bin:${PATH}"
  export PATH
  hash -r 2>/dev/null || true
  if have bun; then
    ok "bun $(bun --version 2>/dev/null || echo ok)"
    return 0
  fi
  warn "bun not on PATH"
  return 1
}

setup_opencode_marketplace() {
  log "OpenCode: alvis/.agents V1 projection"
  if ! have opencode; then
    warn "opencode missing — skip marketplace"
    return 0
  fi
  if ! ensure_bun; then
    warn "bun missing — cannot project plugins into OpenCode"
    return 0
  fi
  ensure_marketplace_clone
  persist_home_path "${HOME}/.local/state/alvis-opencode-v1" "/workspace/.local/state/alvis-opencode-v1"
  local installer="${AGENTS_CLONE_DIR}/scripts/install_opencode.ts"
  if [[ ! -f "$installer" ]]; then
    warn "missing ${installer}"
    return 0
  fi
  # Same set as Codex/Grok. OpenCode has no native marketplace — this projector
  # writes skills/agents under ~/.config/opencode (never edits opencode.json).
  if bun "$installer" --scope user \
      --plugin essential --plugin coding --plugin specification; then
    ok "OpenCode projected essential, coding, specification"
  else
    warn "OpenCode marketplace projection failed"
  fi
}

# Persistence model:
#   Canonical store  = /workspace/<name>   (survives machine reset)
#   App read path    = $HOME/<name>        (symlink → /workspace/...)
# Anything outside /workspace is wiped on restart; re-run install.sh to
# reinstall binaries and re-link homes back onto the persisted trees.

# link_config + persist_home_path: see lib.sh

symlink_configs() {
  log "Persisting harness configs under /workspace (home → workspace symlinks)"
  local ws="/workspace"

  # Apps read $HOME/...; durable store is /workspace/...
  persist_home_path "${HOME}/.claude"      "${ws}/.claude"
  persist_home_path "${HOME}/.claude.json" "${ws}/.claude.json" file
  persist_home_path "${HOME}/.codex"       "${ws}/.codex"
  persist_home_path "${HOME}/.grok"        "${ws}/.grok"
  persist_home_path "${HOME}/.hermes"      "${ws}/.hermes"
  persist_home_path "${HOME}/.honcho"      "${ws}/.honcho"
  persist_home_path "${HOME}/.t3"          "${ws}/.t3"
  persist_home_path "${HOME}/.xurl"        "${ws}/.xurl"
  persist_home_path "${HOME}/.config/opencode" "${ws}/.config/opencode"
  persist_home_path "${HOME}/.local/share/opencode" "${ws}/.local/share/opencode"
  persist_home_path "${HOME}/.local/state/alvis-opencode-v1" "${ws}/.local/state/alvis-opencode-v1"
  # GitHub CLI auth (tokens survive restart when re-linked)
  persist_home_path "${HOME}/.config/gh"   "${ws}/.config/gh"

  export HERMES_HOME="${ws}/.hermes"

  # Marketplace checkout lives at /workspace/alvis/.agents (canonical)
  rm -f "${ws}/alvis-agents"
  ensure_marketplace_clone

  # Convenience aliases under /workspace/configs → same durable trees
  mkdir -p "${ws}/configs"
  link_config "${ws}/configs/claude"      "${ws}/.claude"
  link_config "${ws}/configs/claude.json" "${ws}/.claude.json"
  link_config "${ws}/configs/codex"       "${ws}/.codex"
  link_config "${ws}/configs/grok"        "${ws}/.grok"
  link_config "${ws}/configs/hermes"      "${ws}/.hermes"
  link_config "${ws}/configs/t3"          "${ws}/.t3"
  link_config "${ws}/configs/xurl"        "${ws}/.xurl"
  link_config "${ws}/configs/opencode"    "${ws}/.config/opencode"
  link_config "${ws}/configs/gh"          "${ws}/.config/gh"
  link_config "${ws}/configs/alvis/.agents" "${AGENTS_CLONE_DIR}"
  rm -f "${ws}/configs/alvis-agents"

  ok "durable roots: ${ws}/.claude .codex .grok .hermes .t3 .xurl .config/opencode .config/gh"
}



# Prefer device-code / headless auth for remote hosts:
#   Codex/Grok: --device-auth
#   T3: Tailscale login + t3 pair --tailscale (not Connect tunnels)
#   Claude Code: no RFC 8628 yet — browser OAuth / setup-token only.
install_tailscale() {
  log "Installing Tailscale"
  if have tailscale && have tailscaled; then
    ok "already present: $(tailscale version 2>/dev/null | head -n1 || echo tailscale)"
  else
    if have brew; then
      brew install tailscale || brew install --cask tailscale || true
    fi
    if ! have tailscale; then
      # Official apt/yum installer (may fail on broken distro apt state)
      if ! curl -fsSL https://tailscale.com/install.sh | sh; then
        warn "tailscale install.sh failed — trying static binary"
      fi
    fi
    if ! have tailscale; then
      local ver tarball dir
      ver="$(curl -fsSL "https://pkgs.tailscale.com/stable/?mode=json" | tr -d "\n\t " | sed -n "s/.*\"TarballsVersion\":\"\([^\"]*\)\".*/\1/p" | head -n1)"
      if [[ -z "$ver" ]]; then
        echo "Could not resolve Tailscale static version" >&2
        return 1
      fi
      tarball="tailscale_${ver}_amd64.tgz"
      dir="/tmp/tailscale_${ver}_amd64"
      curl -fsSL -o "/tmp/${tarball}" "https://pkgs.tailscale.com/stable/${tarball}"
      rm -rf "$dir"
      mkdir -p "$dir"
      tar -xzf "/tmp/${tarball}" -C /tmp
      sudo mkdir -p /usr/local/bin
      sudo cp -f "${dir}/tailscale" "${dir}/tailscaled" /usr/local/bin/
      sudo chmod +x /usr/local/bin/tailscale /usr/local/bin/tailscaled
      hash -r 2>/dev/null || true
      ok "installed static tailscale ${ver} to /usr/local/bin"
    fi
  fi

  # Ensure daemon is up with persistent state in /workspace/.tailscale (survives rebuilds; tun or userspace fallback)
  if [[ "$os" == "Linux" ]]; then
    "${ROOT}/bin/tailscale-ensure.sh" || warn "tailscale-ensure failed"
  fi

  if have tailscale; then
    ok "tailscale $(tailscale version 2>/dev/null | head -n1 || true)"
  else
    warn "tailscale not on PATH after install"
    return 1
  fi
}

# Expose the running T3 server over Tailscale Serve and mint a pairing URL.
# Prefer this over T3 Connect managed tunnels (account tunnel limits).
install_gh() {
  log "Installing GitHub CLI (gh)"
  if have gh; then
    ok "already present: $(gh --version 2>/dev/null | head -n1 || echo gh)"
    return 0
  fi
  if have brew; then
    brew install gh
  elif have apt-get; then
    # Official apt repo when possible; fall back to distro package
    if ! apt-cache show gh >/dev/null 2>&1; then
      need_cmd curl
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null || true
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null || true
      sudo apt-get update -qq || true
    fi
    sudo apt-get install -y -qq gh
  elif have dnf; then
    sudo dnf install -y gh
  elif have yum; then
    sudo yum install -y gh
  else
    warn "Install gh from https://cli.github.com then re-run"
    return 1
  fi
  hash -r 2>/dev/null || true
  if have gh; then
    ok "gh $(gh --version 2>/dev/null | head -n1 || true)"
  else
    warn "gh not on PATH after install"
    return 1
  fi
}

# gh auth setup-git only configures the credential helper (HTTPS auth for
# push/pull). Commit author (user.name / user.email) must be set separately
# from the authenticated GitHub account.
# Persist PATH so node/npm/t3/claude/codex/grok/hermes/gh work in new shells.
# Also shim nvm globals into ~/.local/bin (already on most PATH setups).
patch_shell_path() {
  log "Patching PATH for harness tools"
  local marker_begin="# >>> harness-tools PATH (managed by install.sh) >>>"
  local marker_end="# <<< harness-tools PATH (managed by install.sh) <<<"
  local block
  block=$(cat <<'EOF'
# >>> harness-tools PATH (managed by install.sh) >>>
# NPM_CONFIG_PREFIX breaks nvm; clear it so Node 26 + global CLIs (t3) load.
unset NPM_CONFIG_PREFIX
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# Prefer the nvm default Node bin (holds global npm CLIs like t3)
if [ -d "$NVM_DIR/versions/node" ]; then
  _harness_node_bin="$(ls -d "$NVM_DIR"/versions/node/v"${NODE_MAJOR:-26}"* 2>/dev/null | sort -V | tail -n1)/bin"
  if [ -d "$_harness_node_bin" ]; then
    case ":$PATH:" in
      *":$_harness_node_bin:"*) ;;
      *) PATH="$_harness_node_bin:$PATH" ;;
    esac
  fi
  unset _harness_node_bin
fi
for _harness_dir in "$HOME/.local/bin" "$HOME/.grok/bin" "$HOME/.claude/bin"; do
  if [ -d "$_harness_dir" ]; then
    case ":$PATH:" in
      *":$_harness_dir:"*) ;;
      *) PATH="$_harness_dir:$PATH" ;;
    esac
  fi
done
unset _harness_dir
export PATH
export HERMES_HOME="${HERMES_HOME:-/workspace/.hermes}"
# <<< harness-tools PATH (managed by install.sh) <<<
EOF
)

  # Substitute NODE_MAJOR into the block literally for profile files
  block="${block//\$\{NODE_MAJOR:-26\}/${NODE_MAJOR}}"

  write_profile_block() {
    local target="$1"
    mkdir -p "$(dirname "$target")"
    touch "$target"
    if grep -qF "$marker_begin" "$target" 2>/dev/null; then
      # Replace existing managed block
      local tmp
      tmp="$(mktemp)"
      awk -v begin="$marker_begin" -v end="$marker_end" '
        $0 == begin {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
      ' "$target" > "$tmp"
      cat "$tmp" > "$target"
      rm -f "$tmp"
    fi
    printf '\n%s\n' "$block" >> "$target"
    ok "updated ${target}"
  }

  write_profile_block "${HOME}/.bashrc"
  write_profile_block "${HOME}/.profile"
  if [[ -f "${HOME}/.zshrc" ]] || have zsh; then
    write_profile_block "${HOME}/.zshrc"
  fi

  # Apply for the remainder of this script run
  unset NPM_CONFIG_PREFIX
  load_nvm || true
  if type nvm >/dev/null 2>&1; then
    nvm use "${NODE_MAJOR}" >/dev/null 2>&1 || true
  fi
  PATH="${HOME}/.local/bin:${HOME}/.opencode/bin:${HOME}/.grok/bin:${HOME}/.claude/bin:${PATH:-}"
  # Ensure nvm node bin is first
  if have node; then
    local node_bin
    node_bin="$(dirname "$(command -v node)")"
    PATH="${node_bin}:${PATH}"
  fi
  export PATH
  hash -r 2>/dev/null || true

  # Shims into ~/.local/bin so tools work even when nvm isn't sourced
  mkdir -p "${HOME}/.local/bin"
  drop_broken_local_shims
  shim_tool() {
    local name="$1"
    local src dest="${HOME}/.local/bin/${name}"
    src="$(resolve_cmd "$name" || true)"
    if [[ -z "$src" ]]; then
      warn "no ${name} on PATH to shim"
      return 0
    fi
    if [[ "$src" == "$dest" ]]; then
      ok "shim ok: ${src}"
      return 0
    fi
    # Don't replace a real binary with a worse link; refresh symlink if different
    local dest="${HOME}/.local/bin/${name}"
    if [[ -L "$dest" || ! -e "$dest" ]]; then
      ln -sfn "$src" "$dest"
      ok "shim ${dest} → ${src}"
    elif [[ "$dest" -ef "$src" ]]; then
      ok "shim ok: ${dest}"
    else
      warn "skip shim ${name}: ${dest} exists and is not a symlink"
    fi
  }

  shim_tool t3
  shim_tool node
  shim_tool npm
  shim_tool npx
  shim_tool claude
  shim_tool codex
  shim_tool grok
  shim_tool hermes
  shim_tool opencode
  shim_tool xurl
  shim_tool gh

  log "PATH check"
  for c in node npm t3 claude codex grok hermes opencode xurl gh; do
    if have "$c"; then
      ok "$c → $(command -v "$c")"
    else
      warn "$c still missing on PATH"
    fi
  done
}

print_summary() {
  log "Done. Next steps"
  cat <<'NEXT'
  1. Auth is separate — this script never runs it. If you have not logged in:
       ./auth.sh                 # device-code only (codex, grok, gh, opencode)
       ./auth.sh --all           # everything, including Claude
       ./auth.sh --only-claude   # Claude only (no device-code flow)
       ./auth.sh --only-opencode # ChatGPT/Codex + xAI/Grok into OpenCode
  2. In Claude / Codex / Grok, run:
       /essential:install-agents
  3. T3 over Tailscale: ./auth.sh --only-t3   (or: t3 serve --tailscale-serve && t3 pair --tailscale)
  4. Optional extra plugins from alvis marketplace:
       coding | essential | specification | governance | react | web | client | production
  5. Durable configs live UNDER /workspace; $HOME paths symlink into them
     (reset-safe). Re-run ./install.sh after restart to reinstall bins + re-link.
  6. Marketplace checkout: /workspace/alvis/.agents
       OpenCode: bun scripts/install_opencode.ts --scope user --plugin essential --plugin coding --plugin specification
  7. git commits use the gh-authenticated account (user.name / user.email);
     HTTPS git auth uses `gh auth setup-git`
  8. PATH patched in ~/.bashrc + ~/.profile (+ ~/.zshrc); shims in ~/.local/bin
  9. Tailscale + T3 pairing: ./auth.sh --only-tailscale / --only-t3
 10. OpenCode: ./auth.sh --only-opencode  (ChatGPT/Codex + xAI/Grok; needs a TTY)
       # Config still pins openrouter/z-ai/glm-5.3-flash as a default model
 11. Hermes Agent (CLI): binary ~/.local/bin/hermes, home ~/.hermes
       # Default model: OpenRouter z-ai/glm-5.3-flash (Cloudflare only)
       # Needs OPENROUTER_API_KEY in ~/.hermes/.env
       hermes model          # pick provider
       hermes setup          # full wizard (or: hermes setup --portal)
       hermes doctor         # diagnose
       hermes update         # pull latest
 12. Hermes WhatsApp QR: ./auth.sh --only-whatsapp
 13. xurl (X API CLI): ~/.local/bin/xurl
       xurl auth apps add my-app --client-id ID --client-secret SECRET
       xurl auth oauth2 --app my-app   # Native App + PKCE
       xurl auth status
NEXT
}

parse_install_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        cat <<'EOF'
Usage:
  ./install.sh               install packages (after a computer reset)
  ./auth.sh                  log in (device-code services; skip if already in)
  ./auth.sh --all            re-login everything, including Claude
  ./auth.sh --only-NAME      one service (claude has no device-code flow)

This script never runs auth.sh.
Runner host: theriety-github-runner/setup.sh
EOF
        exit 0
        ;;
      --all|--only-*)
        echo "Auth flags belong on ./auth.sh, not ./install.sh" >&2
        echo "  ./auth.sh $1" >&2
        exit 1
        ;;
      *)
        echo "Unknown flag: $1" >&2
        echo "This is the harness installer. For runner host setup see theriety-github-runner/setup.sh" >&2
        exit 1
        ;;
    esac
  done
}

install_main() {
  parse_install_args "$@"
  drop_broken_local_shims
  need_cmd curl
  need_cmd git
  install_node
  # Persist homes under /workspace before installs write auth/config into them
  symlink_configs
  install_claude
  install_codex
  install_grok
  install_opencode
  install_hermes
  install_xurl
  install_t3
  setup_hermes_openrouter_glm
  setup_claude_marketplace
  setup_codex_marketplace
  setup_grok_marketplace
  setup_opencode_marketplace
  # Re-run after installs in case a tool replaced a symlink with a real dir
  symlink_configs
  install_tailscale
  install_gh
  patch_shell_path
  setup_hermes_whatsapp
  print_summary
  log "Install finished. Auth is manual:"
  printf '    ./auth.sh                 # device-code (codex, grok, gh, opencode)\n'
  printf '    ./auth.sh --all           # everything, including Claude\n'
  printf '    ./auth.sh --only-claude   # Claude only\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_main "$@"
fi
