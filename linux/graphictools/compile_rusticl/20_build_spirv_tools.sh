#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/spirv-tools-src"
BUILD_DIR="$ROOT/build"
VENV="$SCRIPT_DIR/env-jinja"
PYTHON="$VENV/bin/python"

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

function activate_virtualenv() {
  log "🔧 Activating Python virtual environment from: $VENV"
  if [[ ! -f "$VENV/bin/activate" ]]; then
    fail "Virtualenv not found at $VENV. Please run the environment setup first."
  fi
  # shellcheck disable=SC1090
  source "$VENV/bin/activate"
  debug "Using Python: $(which python)"
  debug "Using pip: $(which pip)"
  debug "Using ninja: $(which ninja)"
}

function build_spirv_tools() {
  log "🧩 Starting SPIRV-Tools build process..."

  # === Virtualenv Activation ===
  activate_virtualenv

  # === Clone or reset repo ===
  if [[ ! -d "$ROOT/.git" ]]; then
    log "📥 Cloning SPIRV-Tools repository into $ROOT..."
    rm -rf "$ROOT"
    git clone https://github.com/KhronosGroup/SPIRV-Tools.git "$ROOT" || fail "SPIRV-Tools clone failed"
  else
    log "📁 Reusing existing SPIRV-Tools repository at $ROOT"
    cd "$ROOT"
    debug "Resetting local changes"
    git reset --hard
    git clean -fd
    debug "Fetching latest commits"
    git fetch origin
  fi

  cd "$ROOT"
  log "📌 Checking out version v2024.1..."
  git checkout v2024.1 || fail "Checkout failed"
  git submodule update --init --recursive
  "$PYTHON" utils/git-sync-deps || fail "Dependency sync failed"

  curl -sSL https://patch-diff.githubusercontent.com/raw/KhronosGroup/SPIRV-Tools/pull/5534.patch -o 5534.patch
  git apply 5534.patch

  # cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX"
  # cmake --build build
  # sudo cmake --install build


  # === Prepare Build Directory ===
  log "🧹 Cleaning build directory..."
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  debug "PATH: $PATH"
  debug "CMake version: $(cmake --version | head -n1)"
  debug "Python version: $($PYTHON --version)"

  log "⚙️ Configuring CMake with Ninja generator..."
  cmake -S . -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DPython3_EXECUTABLE="$PYTHON" \
    || fail "CMake configure failed"

  log "🧱 Compiling SPIRV-Tools..."
  cmake --build "$BUILD_DIR" -- -j"$(nproc)" || fail "Build failed"

  log "📦 Installing SPIRV-Tools to: $PREFIX"
  sudo cmake --install "$BUILD_DIR" || fail "Install failed"

  # === Validate Install ===
  log "🔍 Validating installation..."
  [[ -f "$PREFIX/lib/libSPIRV-Tools.a" ]] || fail "Missing libSPIRV-Tools.a"
  [[ -f "$PREFIX/lib/cmake/SPIRV-Tools/SPIRV-ToolsConfig.cmake" ]] || fail "Missing SPIRV-ToolsConfig.cmake"
  [[ -x "$PREFIX/bin/spirv-as" ]] || fail "Missing spirv-as binary"
  [[ -x "$PREFIX/bin/spirv-opt" ]] || fail "Missing spirv-opt binary"

  success "SPIRV-Tools built and installed successfully to $PREFIX"
}

# === MAIN ===
build_spirv_tools
