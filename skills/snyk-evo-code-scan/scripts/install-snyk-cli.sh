#!/usr/bin/env sh
# Installs (or reuses) a Snyk CLI that supports `snyk rift test`.
#
# Prints the absolute path of a usable snyk binary on the last line of stdout.
# Everything else goes to stderr so callers can do: SNYK_BIN="$(install-snyk-cli.sh | tail -n1)"
#
# Environment overrides:
#   SNYK_INSTALL_DIR   where to put the binary (default: $HOME/.local/bin)
#   SNYK_CLI_CHANNEL   stable (default) or preview
#   SNYK_FORCE_INSTALL set to 1 to download even if a usable snyk is already on PATH
#
# Exit codes: 0 success, 1 unsupported platform / missing tools, 2 download or checksum failure.

set -eu

log() { printf '%s\n' "$*" >&2; }

supports_rift() {
  "$1" rift test --help 2>/dev/null | grep -q 'rift test'
}

if [ "${SNYK_FORCE_INSTALL:-0}" != "1" ] && command -v snyk >/dev/null 2>&1; then
  existing="$(command -v snyk)"
  if supports_rift "$existing"; then
    log "Using existing Snyk CLI $("$existing" --version 2>/dev/null) at $existing"
    printf '%s\n' "$existing"
    exit 0
  fi
  log "Found $existing ($("$existing" --version 2>/dev/null || echo unknown version)) but it does not support 'snyk rift test'; installing a newer standalone binary."
fi

channel="${SNYK_CLI_CHANNEL:-stable}"
case "$channel" in
  stable|preview) ;;
  *) log "SNYK_CLI_CHANNEL must be 'stable' or 'preview' (got '$channel')"; exit 1 ;;
esac

os="$(uname -s)"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch_suffix="" ;;
  aarch64|arm64) arch_suffix="-arm64" ;;
  *) log "Unsupported CPU architecture: $arch"; exit 1 ;;
esac

case "$os" in
  Linux)
    if [ -f /etc/alpine-release ] || (command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl); then
      asset="snyk-alpine${arch_suffix}"
    else
      asset="snyk-linux${arch_suffix}"
    fi
    ;;
  Darwin)
    asset="snyk-macos${arch_suffix}"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    log "Windows detected. Install with PowerShell instead:"
    log "  Invoke-WebRequest -Uri https://downloads.snyk.io/cli/${channel}/snyk-win.exe -OutFile \"\$env:LOCALAPPDATA\\snyk\\snyk.exe\""
    log "or: npm install -g snyk  /  scoop install snyk"
    exit 1
    ;;
  *)
    log "Unsupported operating system: $os"
    exit 1
    ;;
esac

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -q -O "$2" "$1"; }
else
  log "Neither curl nor wget is available. Install one of them, or run: npm install -g snyk"
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  log "No sha256sum or shasum found; cannot verify the download."
  exit 1
fi

install_dir="${SNYK_INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$install_dir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

base="https://downloads.snyk.io/cli/${channel}"
log "Downloading ${base}/${asset} ..."
fetch "${base}/${asset}" "$tmp/snyk" || { log "Download failed: ${base}/${asset}"; exit 2; }
fetch "${base}/${asset}.sha256" "$tmp/snyk.sha256" || { log "Checksum download failed"; exit 2; }

expected="$(awk '{print $1}' "$tmp/snyk.sha256")"
actual="$(sha256 "$tmp/snyk")"
if [ "$expected" != "$actual" ]; then
  log "Checksum mismatch for ${asset}: expected $expected, got $actual"
  exit 2
fi

chmod +x "$tmp/snyk"
mv "$tmp/snyk" "$install_dir/snyk"
bin="$install_dir/snyk"

if ! supports_rift "$bin"; then
  log "Installed $("$bin" --version) but it does not expose 'snyk rift test'. Try SNYK_CLI_CHANNEL=preview."
  exit 2
fi

log "Installed Snyk CLI $("$bin" --version) at $bin (checksum verified)"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) log "Note: $install_dir is not on PATH. Use the full path or run: export PATH=\"$install_dir:\$PATH\"" ;;
esac
printf '%s\n' "$bin"
