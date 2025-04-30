#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
INSTALL_PREFIX="/opt/lua-5.4"
TMP_DIR="/tmp/lua-54-build"
LUA_BASE_URL="https://www.lua.org/ftp"

# === Helper Functions (Colorful, Emoji, One-liners) ===

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; } # will continue
fail()   { error "$1"; exit 1; }

# === Force Clang ===
log "🛠️ Forcing Clang as the compiler"
export CC=clang
export CXX=clang++

# === STEP 1: Detect latest tarball (stdout=tarball, stderr=debug) ===
function detect_latest_tarball() {
  debug "Fetching directory listing from ${LUA_BASE_URL}/"
  local listing candidates latest

  listing=$(curl -fs "${LUA_BASE_URL}/") \
    || fail "Failed to fetch directory listing"

  debug "Parsing for lua-5.4.x tarballs"
  candidates=$(printf "%s\n" "$listing" \
    | grep -Eo 'lua-5\.4\.[0-9]+\.tar\.gz' \
    | tr -d '\r' \
    | sort -u -V)

  debug "Found candidates:"
  while read -r candidate; do
    debug "  $candidate"
  done <<< "$candidates"

  latest=$(printf "%s\n" "$candidates" | tail -n1)
  [[ -n "$latest" ]] || fail "No lua-5.4.x tarball found!"
  echo "$latest"
}

# === STEP 2: Download, build, install ===
function install_lua() {
  local tarball="$1"
  local release="${tarball%.tar.gz}"   # lua-5.4.7
  local url="${LUA_BASE_URL}/${tarball}"

  log "📥 Downloading $tarball"
  debug "Download URL: $url"

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  curl -fLO "$url" \
    || fail "Failed to download $tarball"

  log "📦 Extracting $tarball"
  tar -xzf "$tarball"
  cd "$release"

  log "🛠️  Building (linux target)"
  make linux -j"$(nproc)" \
    || fail "Build failed"

  log "📦 Installing to $INSTALL_PREFIX"
  sudo make INSTALL_TOP="$INSTALL_PREFIX" install \
    || fail "Install failed"

  log "🔗 Creating symlinks in /usr/local/bin"
  sudo ln -sf "$INSTALL_PREFIX/bin/lua"  /usr/local/bin/lua54
  sudo ln -sf "$INSTALL_PREFIX/bin/luac" /usr/local/bin/luac54

  log "✅ Lua ${release#lua-} installed under $INSTALL_PREFIX"
  "$INSTALL_PREFIX/bin/lua" -v
}

# === MAIN ===
log "🚀 Starting Lua 5.4.x install..."
tarball=$(detect_latest_tarball)
install_lua "$tarball"
