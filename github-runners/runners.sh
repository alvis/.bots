#!/usr/bin/env bash
# preparation-only manager. No registration or listener launch is implemented.
set -euo pipefail
umask 077
readonly VERSION=2.338.0
readonly SHA256=af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32
readonly ROOT=/workspace/shared/theriety-runners
readonly ARCHIVE="$ROOT/downloads/actions-runner-linux-x64-$VERSION.tar.gz"
readonly NAMES=(theriety-oai-1 theriety-oai-2)
fail() { printf '%s\n' "$*" >&2; exit 1; }
rejectActivation() {
  fail 'BLOCKED: an approved and tested isolated network architecture is still required for the intended deployment host. Configure/start remain disabled. No token was read and no runner was launched; shared networking is not enabled.'
}
verify() {
  [[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || fail "Missing regular archive: $ARCHIVE"
  printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum --check --status
  printf 'Verified official runner %s archive SHA-256.\n' "$VERSION"
}
install() {
  verify
  # a pinned, pre-downloaded official archive is used; no network/package install.
  # existing installations are never overwritten, including registration state.
  for name in "${NAMES[@]}"; do
    [[ ! -e "$ROOT/$name" && ! -L "$ROOT/$name" ]] || fail "Refusing to overwrite existing $ROOT/$name; use verify/status."
  done
  for name in "${NAMES[@]}"; do
    mkdir -m 700 -p "$ROOT/$name/runner" "$ROOT/$name/home" "$ROOT/$name/tmp"
    tar --extract --gzip --file "$ARCHIVE" --directory "$ROOT/$name/runner" --no-same-owner --no-same-permissions
  done
  printf 'Installed two separate runner trees. Nothing registered or started.\n'
}
showStatus() {
  printf 'Organization: theriety; intended custom label: theriety-oai\n'
  printf 'Activation: BLOCKED (network architecture approval/testing required); autostart: not installed\n'
  for name in "${NAMES[@]}"; do
    local installed=no configured=no
    [[ ! -f "$ROOT/$name/runner/bin/Runner.Listener" ]] || installed=yes
    [[ ! -f "$ROOT/$name/runner/.runner" ]] || configured=yes
    printf '%s: binary present=%s; registration file present=%s\n' "$name" "$installed" "$configured"
  done
  printf 'This preparation-only manager has never started a listener; it does not infer remote registration or manage externally launched processes.\n'
}
case "${1:-help}" in
  install) [[ $# == 1 ]] || fail 'install takes no arguments'; install ;;
  verify) [[ $# == 1 ]] || fail 'verify takes no arguments'; verify ;;
  configure|start) rejectActivation ;;
  stop) fail 'No managed listener can be started by this scaffold. Stop is not implemented; no unrelated process was signaled.' ;;
  status) showStatus ;;
  help|--help|-h) printf '%s\n' 'Usage: runners.sh {install|verify|configure|start|stop|status}' 'configure/start fail closed; stop never signals unrelated processes.' ;;
  *) fail 'Unknown command; use --help' ;;
esac
