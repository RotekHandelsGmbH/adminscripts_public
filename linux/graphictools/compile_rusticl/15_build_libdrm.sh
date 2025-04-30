#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# === Build libdrm ===
function build_libdrm() {
  log "Building libdrm >= 2.4.121..."

  # Clone specific libdrm branch
  git clone --depth=1 --branch libdrm-2.4.121 \
    https://gitlab.freedesktop.org/mesa/drm.git "$ROOT/drm" \
    || fail "Failed to clone libdrm repository"

  # Configure with Meson
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    || fail "Meson setup for libdrm failed"

  # Build and install
  ninja -C "$ROOT/drm/build" || fail "libdrm build failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install failed"

  # Update pkg-config path and report version
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  debug "libdrm_amdgpu version: $(pkg-config --modversion libdrm_amdgpu || echo 'Not found')"
}

# === MAIN ===
build_libdrm
log "libdrm build complete."
