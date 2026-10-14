#!/usr/bin/env bash
# Shared helpers for install.sh and auth.sh.
# Callers must set ROOT to their own directory before sourcing, e.g.:
#   ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib.sh
#   source "${ROOT}/lib.sh"

log() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ✓ %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }
# First real executable on PATH (skips dangling / circular shims).
resolve_cmd() {
  local name="$1" dir cand tgt
  local IFS=':'
  for dir in $PATH; do
    [[ -n "$dir" ]] || dir="."
    cand="${dir}/${name}"
    if [[ -L "$cand" ]]; then
      tgt="$(readlink "$cand" 2>/dev/null || true)"
      if [[ "$tgt" == "$cand" || "$tgt" == "$name" || ! -e "$cand" ]]; then
        continue
      fi
    fi
    if [[ -f "$cand" && -x "$cand" ]]; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

have() { resolve_cmd "$1" >/dev/null; }

# Drop ~/.local/bin entries that point at themselves or nowhere.
drop_broken_local_shims() {
  local f tgt
  [[ -d "${HOME}/.local/bin" ]] || return 0
  for f in "${HOME}/.local/bin"/*; do
    [[ -L "$f" ]] || continue
    tgt="$(readlink "$f" 2>/dev/null || true)"
    if [[ "$tgt" == "$f" || "$tgt" == "$(basename "$f")" || ! -e "$f" ]]; then
      rm -f "$f"
      warn "removed broken shim ${f}"
    fi
  done
  hash -r 2>/dev/null || true
}

need_cmd() {
  if ! have "$1"; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

# Set global `os` (Darwin|Linux) or exit.
detect_os() {
  os="$(uname -s)"
  case "$os" in
    Darwin|Linux) ;;
    *)
      echo "This script supports macOS and Linux only (got: $os)." >&2
      exit 1
      ;;
  esac
}

# Usage: link_config <link-path> <target-path>
# Creates link-path → target-path (target is the real data).
link_config() {
  local link="$1"
  local target="$2"

  mkdir -p "$(dirname "$link")"
  # Create missing directory targets only (not missing files like *.json)
  if [[ ! -e "$target" && ! -L "$target" && "$target" != *.json ]]; then
    mkdir -p "$target"
  fi

  if [[ -L "$link" ]]; then
    local current
    current="$(readlink "$link")"
    if [[ "$current" == "$target" ]]; then
      ok "symlink ok: ${link} → ${target}"
      return 0
    fi
    rm -f "$link"
  elif [[ -e "$link" ]]; then
    warn "skip ${link}: path exists and is not a symlink"
    return 0
  fi

  # Only link when the target exists (or is an allowed empty dir we just made)
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    warn "skip ${link}: target missing (${target})"
    return 0
  fi

  ln -sfn "$target" "$link"
  ok "linked ${link} → ${target}"
}

# Move app state into /workspace and point $HOME paths at it.
# Usage: persist_home_path <home-relative-or-abs> <workspace-abs> [file|dir]
# Persistence model:
#   Canonical store  = /workspace/<name>   (survives machine reset)
#   App read path    = $HOME/<name>        (symlink → /workspace/...)
persist_home_path() {
  local home_path="$1"
  local ws_path="$2"
  local kind="${3:-dir}"  # dir | file

  # Normalize home_path
  if [[ "$home_path" != /* ]]; then
    home_path="${HOME}/${home_path}"
  fi

  mkdir -p "$(dirname "$ws_path")"
  mkdir -p "$(dirname "$home_path")"

  # Case A: workspace already holds data, home is correct symlink
  if [[ -L "$home_path" ]]; then
    local cur
    cur="$(readlink "$home_path")"
    if [[ "$cur" == "$ws_path" ]]; then
      if [[ "$kind" == "dir" && ! -e "$ws_path" ]]; then
        mkdir -p "$ws_path"
      fi
      ok "persist ok: ${home_path} → ${ws_path}"
      return 0
    fi
    # Wrong symlink (often old /workspace → $HOME direction) — drop it
    rm -f "$home_path"
  fi

  # Case B: /workspace path is a leftover symlink into $HOME — replace with real tree
  if [[ -L "$ws_path" ]]; then
    local wscur
    wscur="$(readlink "$ws_path")"
    rm -f "$ws_path"
    # If it pointed at home_path and home still has real data, we'll move below
    if [[ -e "$home_path" && ! -L "$home_path" ]]; then
      :
    elif [[ -e "$wscur" && "$wscur" != "$home_path" ]]; then
      # Unusual: copy from old target
      if [[ "$kind" == "dir" ]]; then
        mkdir -p "$ws_path"
        cp -a "$wscur"/. "$ws_path"/ 2>/dev/null || true
      else
        cp -a "$wscur" "$ws_path" 2>/dev/null || true
      fi
    fi
  fi

  # Case C: real data still under $HOME — move into /workspace
  if [[ -e "$home_path" && ! -L "$home_path" ]]; then
    if [[ -e "$ws_path" ]]; then
      # Both exist: keep workspace, back up home aside
      local bak="${home_path}.pre-persist.$$"
      mv "$home_path" "$bak"
      warn "both ${home_path} and ${ws_path} existed — kept workspace, home backup at ${bak}"
    else
      mv "$home_path" "$ws_path"
      ok "moved ${home_path} → ${ws_path}"
    fi
  fi

  # Case D: nothing yet — create empty workspace dir (skip for optional files)
  if [[ ! -e "$ws_path" && ! -L "$ws_path" ]]; then
    if [[ "$kind" == "dir" ]]; then
      mkdir -p "$ws_path"
      ok "created ${ws_path}"
    else
      # optional file (e.g. .claude.json) — nothing to link yet
      return 0
    fi
  fi

  # Point home → workspace
  rm -f "$home_path"
  ln -sfn "$ws_path" "$home_path"
  ok "persist: ${home_path} → ${ws_path}"
}

# Run detect_os on source so `os` is available to callers.
detect_os
