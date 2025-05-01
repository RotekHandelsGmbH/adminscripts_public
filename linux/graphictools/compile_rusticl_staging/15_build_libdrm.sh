#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === Helper Functions (Colorful, Emoji, One-liners) ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'

log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

log "🛠️ Cleaning up old build directory"
rm -rf "${ROOT}/drm"

# === Force GCC ===
log "🛠️ Forcing GCC as the compiler"
export CC=gcc
export CXX=g++

# === Build libdrm with aggressive optimization and PGO ===
function build_libdrm() {
  log "Building libdrm >= 2.4.121 with PGO and LTO..."

  # Clone if not already cloned
  if [[ ! -d "$ROOT/drm" ]]; then
    git clone --depth=1 --branch libdrm-2.4.121 \
      https://gitlab.freedesktop.org/mesa/drm.git "$ROOT/drm" \
      || fail "Failed to clone libdrm repository"
  fi

  # === First pass: generate profiling data ===
  log "🔁 First pass: compiling with -fprofile-generate"
  export CFLAGS="-O3 -march=native -flto -fPIC -fvisibility=hidden -fomit-frame-pointer -DNDEBUG -fprofile-generate"
  export CXXFLAGS="$CFLAGS"
  # -O3                   # Enable highest level of optimization (aggressive inlining, loop unrolling, vectorization)
  # -march=native         # Optimize code for the local CPU architecture (may break portability)
  # -flto                 # Enable Link Time Optimization (LTO) for better cross-module optimization
  # -fPIC                 # Generate position-independent code (required for shared libraries)
  # -fvisibility=hidden   # Hide all symbols by default; only explicitly exported ones are visible (improves load time and security)
  # -fomit-frame-pointer  # Omit the frame pointer to free a register (slightly faster, but makes debugging stack traces harder)
  # -DNDEBUG              # Disable debug `assert()` and other debug-only code (used in production builds)
  # -fprofile-generate    # Instrument the program to collect profiling data at runtime (for use with PGO - Profile Guided Optimization)

  # export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -shared  -fprofile-generate"
  export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -fprofile-generate"
  # -flto                  # Enable Link Time Optimization (LTO) during linking for cross-module inlining and better optimization
  # -Wl,-O1                # Pass optimization level 1 to the linker (balance between speed and link-time complexity)
  # -Wl,--as-needed        # Only link shared libraries that are actually used (reduces dependencies and load time)
  # -Wl,--strip-all        # Strip all symbol information from the final binary (smaller size, but no debugging symbols)
  # -shared                # Produce a shared object (.so) instead of an executable
  # -fprofile-generate    # Instrument the program to collect profiling data at runtime (for use with PGO - Profile Guided Optimization)

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    || fail "Meson setup (generate phase) failed"

  ninja -v -C "$ROOT/drm/build" || fail "libdrm build (generate) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (generate) failed"

  # === Simulate a workload that uses libdrm (example test app) ===
  log "⚙️ Running dummy workload to generate PGO data..."
  cat > "$ROOT/test_pgo.c" <<EOF
#include <stdio.h>
#include <xf86drm.h>
int main() {
    int version = drmGetVersion(0) != NULL;
    printf("drmGetVersion call result: %d\\n", version);
    return 0;
}
EOF

  gcc "$ROOT/test_pgo.c" -o "$ROOT/test_pgo" \
    -I"$PREFIX/include" \
    -I"$PREFIX/include/libdrm" \
    -L"$PREFIX/lib" -ldrm || fail "Failed to build test workload"

  DRM_DIR=/dev/dri
  if [[ -e "$DRM_DIR/card0" ]]; then
    "$ROOT/test_pgo" || warn "Test workload failed to run"
  else
    warn "No /dev/dri/card0 found. Skipping real PGO run"
  fi

  # === Second pass: use collected profile data ===
  log "🔁 Second pass: compiling with -fprofile-use"
  export CFLAGS="-O3 -march=native -mtune=native -flto -fprofile-use -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto -fprofile-use"

  export CFLAGS="-O3 -march=native -flto -fPIC -fvisibility=hidden -fomit-frame-pointer -DNDEBUG -fprofile-use"
  export CXXFLAGS="$CFLAGS"
  # -O3                   # Enable highest level of optimization (aggressive inlining, loop unrolling, vectorization)
  # -march=native         # Optimize code for the local CPU architecture (may break portability)
  # -flto                 # Enable Link Time Optimization (LTO) for better cross-module optimization
  # -fPIC                 # Generate position-independent code (required for shared libraries)
  # -fvisibility=hidden   # Hide all symbols by default; only explicitly exported ones are visible (improves load time and security)
  # -fomit-frame-pointer  # Omit the frame pointer to free a register (slightly faster, but makes debugging stack traces harder)
  # -DNDEBUG              # Disable debug `assert()` and other debug-only code (used in production builds)
  # -fprofile-use        # Use collected profiling data (from -fprofile-generate) to optimize code layout, inlining, and branch prediction

  # export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -shared -fprofile-use"
  export LDFLAGS="-flto -Wl,-O1 -Wl,--as-needed -Wl,--strip-all -fprofile-use"
  # -flto                  # Enable Link Time Optimization (LTO) during linking for cross-module inlining and better optimization
  # -Wl,-O1                # Pass optimization level 1 to the linker (balance between speed and link-time complexity)
  # -Wl,--as-needed        # Only link shared libraries that are actually used (reduces dependencies and load time)
  # -Wl,--strip-all        # Strip all symbol information from the final binary (smaller size, but no debugging symbols)
  # -shared                # Produce a shared object (.so) instead of an executable
  # -fprofile-use        # Use collected profiling data (from -fprofile-generate) to optimize code layout, inlining, and branch prediction

  rm -rf "$ROOT/drm/build"
  meson setup "$ROOT/drm/build" "$ROOT/drm" \
    -Dprefix="$PREFIX" \
    -Damdgpu=enabled \
    -Dbuildtype=release \
    || fail "Meson setup (use phase) failed"

  ninja -v -C "$ROOT/drm/build" || fail "libdrm build (use) failed"
  sudo ninja -C "$ROOT/drm/build" install || fail "libdrm install (use) failed"

  # Confirm version
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
  debug "libdrm_amdgpu version: $(pkg-config --modversion libdrm_amdgpu || echo 'Not found')"
  success "libdrm build complete with PGO optimization."
}

# === MAIN ===
build_libdrm
