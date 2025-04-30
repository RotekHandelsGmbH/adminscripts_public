#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/spirv-tools-src"
BUILD_DIR_GEN="$ROOT/build-gen"
BUILD_DIR_USE="$ROOT/build-use"
PROFILE_DIR="$SCRIPT_DIR/pgo-profile"
VENV="$SCRIPT_DIR/env-jinja"
PYTHON="$VENV/bin/python"

EXAMPLE_SPIRV="$SCRIPT_DIR/example.spv"

# === CMAKE FLAGS ===
CMAKE_COMMON_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DPython3_EXECUTABLE="$PYTHON"
  -DSPIRV_WERROR=OFF
  -DSPIRV_TOOLS_INSTALL_CMAKE_CONFIG=ON
)

# === COLORS & LOGGING ===
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

# === HELPERS ===
activate_virtualenv() {
  log "🔧 Activating Python virtual environment from: $VENV"
  if [[ ! -f "$VENV/bin/activate" ]]; then
    fail "Virtualenv not found at $VENV. Please run the environment setup first."
  fi
  source "$VENV/bin/activate"
}

fetch_repo() {
  if [[ ! -d "$ROOT/.git" ]]; then
    log "📥 Cloning SPIRV-Tools repository into $ROOT..."
    rm -rf "$ROOT"
    git clone https://github.com/KhronosGroup/SPIRV-Tools.git "$ROOT" || fail "Clone failed"
  fi
  cd "$ROOT"
  git reset --hard && git clean -fd
  git fetch origin
  git checkout v2024.1 || fail "Checkout failed"
  git submodule update --init --recursive
  "$PYTHON" utils/git-sync-deps || fail "Dependency sync failed"

  curl -sSL https://patch-diff.githubusercontent.com/raw/KhronosGroup/SPIRV-Tools/pull/5534.patch -o 5534.patch
  git apply 5534.patch || warn "Patch may already be applied"
}

build_with_flags() {
  local BUILD_DIR=$1
  local PROFILE_FLAG=$2
  local TYPE_LABEL=$3

  log "⚙️ Building ($TYPE_LABEL pass)..."
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"

  export CFLAGS="-O3 -march=native -mtune=native -flto $PROFILE_FLAG -fomit-frame-pointer -fPIC"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -flto $PROFILE_FLAG"

  cmake -S "$ROOT" -B "$BUILD_DIR" -G Ninja \
    "${CMAKE_COMMON_FLAGS[@]}" \
    || fail "CMake configure failed"

  cmake --build "$BUILD_DIR" -- -j"$(nproc)" || fail "Build failed"
}

generate_example_spirv() {
  log "📝 Creating simple SPIR-V binary for profiling..."
  cat > "$SCRIPT_DIR/example.vert" <<EOF
#version 450
void main() {}
EOF
  "$BUILD_DIR_GEN/tools/glslang/glslangValidator" -V "$SCRIPT_DIR/example.vert" -o "$EXAMPLE_SPIRV" || warn "glslangValidator failed"
}

run_profiling_workload() {
  log "🚀 Running profiling workload..."
  export GCOV_PREFIX="$PROFILE_DIR"
  export GCOV_PREFIX_STRIP=10

  generate_example_spirv

  "$BUILD_DIR_GEN/tools/as/spirv-as" "$EXAMPLE_SPIRV" -o /dev/null || warn "spirv-as failed"
  "$BUILD_DIR_GEN/tools/opt/spirv-opt" "$EXAMPLE_SPIRV" -O -o /dev/null || warn "spirv-opt failed"
}

install_final_build() {
  log "📦 Installing optimized build..."
  sudo cmake --install "$BUILD_DIR_USE" || fail "Install failed"
}

validate_install() {
  log "🔍 Validating installation..."
  [[ -f "$PREFIX/lib/libSPIRV-Tools.a" ]] || fail "Missing libSPIRV-Tools.a"
  [[ -f "$PREFIX/lib/cmake/SPIRV-Tools/SPIRV-ToolsConfig.cmake" ]] || fail "Missing SPIRV-ToolsConfig.cmake"
  [[ -x "$PREFIX/bin/spirv-as" ]] || fail "Missing spirv-as"
  [[ -x "$PREFIX/bin/spirv-opt" ]] || fail "Missing spirv-opt"
  success "SPIRV-Tools built and installed successfully to $PREFIX"
}

main() {
  activate_virtualenv
  fetch_repo

  log "🔁 First pass: -fprofile-generate"
  build_with_flags "$BUILD_DIR_GEN" "-fprofile-generate=$PROFILE_DIR" "Generate"
  run_profiling_workload

  log "🎯 Second pass: -fprofile-use"
  build_with_flags "$BUILD_DIR_USE" "-fprofile-use=$PROFILE_DIR -fprofile-correction -Wno-missing-profile" "Use"
  install_final_build
  validate_install
}

main
