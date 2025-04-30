#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/spirv-tools-src"
BUILD_DIR_GEN="$ROOT/build-gen"
BUILD_DIR_USE="$ROOT/build-use"
VENV="$SCRIPT_DIR/env-jinja"
PYTHON="$VENV/bin/python"
PROFILE_DIR="$SCRIPT_DIR/pgo-profile"

# === Helper Functions (Colorful, Emoji, One-liners) ===

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'
log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

activate_virtualenv() {
  log "🔧 Activating Python virtual environment from: $VENV"
  if [[ ! -f "$VENV/bin/activate" ]]; then
    fail "Virtualenv not found at $VENV. Please run the environment setup first."
  fi
  source "$VENV/bin/activate"
  debug "Using Python: $(which python)"
  debug "Using pip: $(which pip)"
  debug "Using ninja: $(which ninja)"
}

fetch_repo() {
  if [[ ! -d "$ROOT/.git" ]]; then
    log "📥 Cloning SPIRV-Tools repository into $ROOT..."
    rm -rf "$ROOT"
    git clone https://github.com/KhronosGroup/SPIRV-Tools.git "$ROOT" || fail "SPIRV-Tools clone failed"
  else
    log "📁 Reusing existing SPIRV-Tools repository at $ROOT"
    cd "$ROOT"
    git reset --hard && git clean -fd
    git fetch origin
  fi

  cd "$ROOT"
  git checkout v2024.1 || fail "Checkout failed"
  git submodule update --init --recursive
  "$PYTHON" utils/git-sync-deps || fail "Dependency sync failed"

  curl -sSL https://patch-diff.githubusercontent.com/raw/KhronosGroup/SPIRV-Tools/pull/5534.patch -o 5534.patch
  git apply 5534.patch
}

build_with_flags() {
  local BUILD_DIR=$1
  local PROFILE_FLAG=$2
  local BUILD_TYPE=$3

  log "🧹 Cleaning $BUILD_TYPE build directory..."
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  export CFLAGS="-O3 -march=native -mtune=native -flto $PROFILE_FLAG -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto $PROFILE_FLAG"

  cmake -S "$ROOT" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DPython3_EXECUTABLE="$PYTHON" || fail "CMake configure failed"

  cmake --build "$BUILD_DIR" -- -j"$(nproc)" || fail "Build failed"
}

run_profiling_workload() {
  log "🚀 Running workload to generate profiling data..."
  "$BUILD_DIR_GEN/tools/opt/spirv-opt" --version || warn "Run real workloads here to generate full profile"
}

install_final_build() {
  sudo cmake --install "$BUILD_DIR_USE" || fail "Install failed"
}

validate_install() {
  log "🔍 Validating installation..."
  [[ -f "$PREFIX/lib/libSPIRV-Tools.a" ]] || fail "Missing libSPIRV-Tools.a"
  [[ -f "$PREFIX/lib/cmake/SPIRV-Tools/SPIRV-ToolsConfig.cmake" ]] || fail "Missing SPIRV-ToolsConfig.cmake"
  [[ -x "$PREFIX/bin/spirv-as" ]] || fail "Missing spirv-as binary"
  [[ -x "$PREFIX/bin/spirv-opt" ]] || fail "Missing spirv-opt binary"
  success "SPIRV-Tools built and installed successfully to $PREFIX"
}

main() {
  activate_virtualenv
  fetch_repo

  # === First Pass: Profile Generation ===
  log "🔁 First pass: compiling with -fprofile-generate"
  build_with_flags "$BUILD_DIR_GEN" "-fprofile-generate=$PROFILE_DIR" "generate"
  run_profiling_workload

  # === Second Pass: Use Profiling Data ===
  log "🎯 Second pass: compiling with -fprofile-use"
  build_with_flags "$BUILD_DIR_USE" "-fprofile-use=$PROFILE_DIR -fprofile-correction" "use"
  install_final_build
  validate_install
}

main
