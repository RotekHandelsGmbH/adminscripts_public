#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/env-jinja"
BUILD_DIR="$ROOT/build"
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
ICD_DIR="$PREFIX/etc/OpenCL/vendors"
CLEAN_ICD="rusticl.icd"
SO_TARGET="$PREFIX/lib/libMesaOpenCL.so.1"
LOCAL_LUA="/opt/lua-5.4"

export LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
export PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:$PATH"


rm -rf "$BUILD_DIR"
rm -rf "$ROOT/mesa"


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

# === Force gcc ===
# export CC=gcc
# export CXX=g++

# === Activate Python venv & Rust ===
function activate_env() {
  [[ -f "${VENV}/bin/activate" ]] \
    || fail "Virtualenv not found at ${VENV}. Run setup first."
  # shellcheck disable=SC1090
  source "${VENV}/bin/activate"
  debug "Python -> $(which python) ($(python --version 2>&1))"
  debug "Pip    -> $(which pip)"

  log "Ensuring setuptools, packaging and Mako ≥0.8.0..."
  pip install --upgrade setuptools packaging "mako>=0.8.0" \
    || fail "Failed to install/upgrade setuptools/packaging or mako"

  log "Ensuring Meson, Ninja & PyYAML..."
  pip install --upgrade meson ninja PyYAML \
    || fail "Failed to install Meson/Ninja/PyYAML"

  # Rust
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  command -v rustc  >/dev/null || fail "rustc not found"
  command -v bindgen >/dev/null || fail "bindgen not found"
  debug "Rustc  -> $(rustc --version 2>&1)"
  debug "Bindgen-> $(bindgen --version 2>&1)"
}

# === Build Mesa ===
function build_mesa() {
  log "Building Mesa with Rusticl…"
  activate_env

  # Lua detection
  if pkg-config --exists lua5.4; then
    debug "Using system lua5.4"
  else
    if [[ -d "$LOCAL_LUA" ]]; then
      log "System lua5.4-dev not found – falling back to $LOCAL_LUA"
      # avoid unbound-variable errors with parameter defaults
      export PKG_CONFIG_PATH="$LOCAL_LUA/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
      export CPPFLAGS="-I$LOCAL_LUA/include ${CPPFLAGS:-}"
      export LDFLAGS="-L$LOCAL_LUA/lib ${LDFLAGS:-}"
    else
      fail "lua5.4 not found system‑wide and no local build at $LOCAL_LUA"
    fi
  fi

  # Clone/update Mesa
  if [[ -d "$ROOT/mesa/.git" ]]; then
    log "Updating Mesa checkout…"
    cd "$ROOT/mesa"
    git fetch --depth=1 origin main || fail "git fetch failed"
    git reset --hard origin/main     || fail "git reset failed"
  else
    log "Cloning Mesa into $ROOT/mesa…"
    git clone --depth=1 https://gitlab.freedesktop.org/mesa/mesa.git "$ROOT/mesa" \
      || fail "Mesa clone failed"
    cd "$ROOT/mesa"
  fi

  # Prepare build dir
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"

  log "Configuring Mesa (Meson)…"


meson setup "$BUILD_DIR" . \
  -Dprefix="$PREFIX" \
  -Dbuildtype=release \
  -Dgallium-drivers=radeonsi,llvmpipe \
  -Dvulkan-drivers=amd \
  -Dllvm=enabled \
  -Dshared-llvm=disabled \
  -Dgallium-rusticl=true \
  -Drust_std=2021 \
  -Dplatforms=x11 \
  -Dgallium-va=enabled \
  -Dgallium-vdpau=enabled \
  -Dgles1=disabled \
  -Dgles2=enabled \
  -Dopengl=true \
  -Dglvnd=enabled \
  --warnlevel=1

  log "Compiling Mesa…"
  ninja -C "$BUILD_DIR" -v || fail "Mesa build failed"

  log "Installing Mesa…"
  sudo ninja -C "$BUILD_DIR" install || fail "Mesa install failed"
}

# === Finalize OpenCL ICD ===
function finalize_opencl() {
  log "Finalizing OpenCL ICD…"
  local RSO
  RSO=$(find "$BUILD_DIR" -name 'libRusticlOpenCL.so.1.0.0' | head -n1)
  [[ -f "$RSO" ]] || fail "libRusticlOpenCL.so.1.0.0 not found"

  sudo cp "$RSO" "$PREFIX/lib/"
  sudo ln -sf "$PREFIX/lib/libRusticlOpenCL.so.1.0.0" "$SO_TARGET"
  sudo ldconfig

  sudo mkdir -p "$ICD_DIR"
  echo "$SO_TARGET" | sudo tee "$ICD_DIR/$CLEAN_ICD" >/dev/null
  log "Wrote ICD: $ICD_DIR/$CLEAN_ICD"
}

# === MAIN ===
build_mesa
finalize_opencl
log "🎉 Mesa + Rusticl built, OpenCL ICD installed."
