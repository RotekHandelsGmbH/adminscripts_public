#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
INSTALL_PREFIX="/opt/lua-5.4"
TMP_DIR="/tmp/lua-54-build"
LUA_REPO_URL="https://gitlab.com/lua/lua.git"

# === Helper Functions ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === Compiler Optimization Flags ===
log "🛠️ Setting compiler and linker flags for aggressive performance optimization with PGO"
export CC=gcc
export CXX=g++
export CFLAGS="-Ofast -march=native -mtune=native -flto -fprofile-generate -fomit-frame-pointer -fPIC"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O3 -flto -fprofile-generate"

# === STEP 1: Get Latest 5.4.x Tag from Git ===
detect_latest_54_tag() {
  log "🔍 Cloning Lua repo and detecting latest 5.4.x tag"
  rm -rf "$TMP_DIR"
  git clone --quiet --mirror "$LUA_REPO_URL" "$TMP_DIR/lua.git" || fail "Failed to clone Lua repo"

  cd "$TMP_DIR"
  git --git-dir=lua.git tag -l | grep -E "^v?5\.4(\.[0-9]+)?$" | sort -V | tee /dev/stderr | tail -n1
}

# === STEP 2: Checkout, Build and Install ===
install_lua_from_git_tag() {
  local tag="$1"
  log "📥 Checking out Lua $tag"

  git clone --quiet "$TMP_DIR/lua.git" "$TMP_DIR/lua"
  cd "$TMP_DIR/lua"
  git checkout --quiet "$tag" || fail "Failed to checkout tag $tag"

  log "🛠️  Building with profiling instrumentation (first pass)"
  make clean >/dev/null 2>&1 || true
  make linux -j"$(nproc)" || fail "Profile-gen build failed"

  log "🏃 Running Lua to generate profile data"
  "$TMP_DIR/lua/src/lua" -e "for i=1,1e6 do local x=math.sin(i) end"

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

  log "✅ Lua ${tag#v} installed under $INSTALL_PREFIX"
  "$INSTALL_PREFIX/bin/lua" -v
}

# === MAIN ===
log "🚀 Starting Lua 5.4.x install from Git tags..."
tag=$(detect_latest_54_tag)
install_lua_from_git_tag "$tag"
