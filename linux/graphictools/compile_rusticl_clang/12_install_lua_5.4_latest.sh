#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
INSTALL_PREFIX="/opt/lua-5.4"
TMP_DIR="/tmp/lua-54-build"
LUA_BASE_URL="https://www.lua.org/ftp"

# === Helper Functions ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === Force GCC ===
log "🛠️ Forcing GCC as the compiler"
export CC=gcc
export CXX=g++

# === Compiler Optimization Flags ===
log "🛠️ Setting compiler and linker flags for aggressive performance optimization with PGO"
export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-generate -fomit-frame-pointer -fPIC"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O3 -flto -fprofile-generate"

# === STEP 1: Detect Latest Lua 5.4.x Tarball ===
detect_latest_tarball() {
  log "🔍 Detecting latest Lua 5.4.x tarball from $LUA_BASE_URL" >&2
  local listing candidates latest
  listing=$(curl -fs "$LUA_BASE_URL/") || fail "Failed to fetch tarball listing"
  candidates=$(echo "$listing" | grep -Eo 'lua-5\.4\.[0-9]+\.tar\.gz' | sort -V | uniq)
  latest=$(echo "$candidates" | tail -n1)
  [[ -n "$latest" ]] || fail "No Lua 5.4.x tarball found"
  echo "$latest"
}

# === STEP 2: Download, Build, PGO Optimize, Install ===
install_lua_from_tarball() {
  local tarball="$1"
  local release="${tarball%.tar.gz}"
  local url="${LUA_BASE_URL}/${tarball}"

  log "📥 Downloading $tarball from $url"
  [[ -z "$tarball" ]] && fail "Tarball name is empty"
  [[ -z "$url" ]] && fail "URL is empty"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"
  curl -fLO "$url" || fail "Failed to download $tarball"

  log "📦 Extracting $tarball"
  tar -xzf "$tarball"
  cd "$release"

  log "🛠️  Building with profiling instrumentation (first pass)"
  make clean >/dev/null 2>&1 || true
  make linux -j"$(nproc)" || fail "Profile-gen build failed"

  log "🏃 Running Lua to generate profile data"
  ./src/lua -e "for i=1,1e6 do local x=math.sin(i) end"

  log "🔁 Rebuilding with profile-optimized flags"
  export CFLAGS="-Ofast -march=native -mtune=native -flto -fprofile-use -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-use"
  make clean >/dev/null 2>&1 || true
  make linux -j"$(nproc)" || fail "Profile-use build failed"

  log "📦 Installing to $INSTALL_PREFIX"
  sudo make INSTALL_TOP="$INSTALL_PREFIX" install || fail "Install failed"

  log "🔗 Creating symlinks in /usr/local/bin"
  sudo ln -sf "$INSTALL_PREFIX/bin/lua"  /usr/local/bin/lua54
  sudo ln -sf "$INSTALL_PREFIX/bin/luac" /usr/local/bin/luac54

  log "✅ Lua ${release#lua-} installed under $INSTALL_PREFIX"
  "$INSTALL_PREFIX/bin/lua" -v
}

# === MAIN ===
log "🚀 Starting Lua 5.4.x install from tarball..."
tarball=$(detect_latest_tarball)
install_lua_from_tarball "$tarball"
