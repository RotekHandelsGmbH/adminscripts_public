#!/usr/bin/env bash
set -euo pipefail
set -x

# === CONFIGURATION ===
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spirv-llvm-translator-build"
PROFILE_DIR="$ROOT/pgo-profile"
BUILD_DIR_GEN="$ROOT/build-gen"
BUILD_DIR_USE="$ROOT/build-use"

PROFILE_FLAG=""
export CFLAGS="-O3 -march=native -mtune=native -flto $PROFILE_FLAG -fomit-frame-pointer -fPIC"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O3 -flto $PROFILE_FLAG"

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

# === BUILD FUNCTIONS ===

function build_with_flags() {
  local build_dir="$1"
  local extra_flags="$2"
  local stage_name="$3"

  log "🔧 [$stage_name] Configuring with flags: $extra_flags"
  rm -rf "$build_dir"
  cmake -S spirv-llvm-translator -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DLLVM_CONFIG="$LLVM_CONFIG" \
    -DCMAKE_PREFIX_PATH="$($LLVM_CONFIG --prefix);$PREFIX" \
    -DLLVM_DIR="$($LLVM_CONFIG --prefix)/lib/cmake/llvm" \
    -DCMAKE_C_FLAGS="$CFLAGS $extra_flags" \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS $extra_flags" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"

  cmake --build "$build_dir" --target llvm-spirv -- -j$(nproc) || fail "Build failed at stage: $stage_name"
}

function find_llvm_spirv_binary() {
  local search_root="$1"
  find "$search_root" -type f -name "llvm-spirv" -executable | head -n 1
}

function run_profiling_workload() {
  log "🏃 Running profiling workload..."
  local spirv_bin
  spirv_bin="$(find_llvm_spirv_binary "$BUILD_DIR_GEN")"

  [[ -n "$spirv_bin" && -x "$spirv_bin" ]] || fail "SPIR-V binary not found in build-gen!"
  "$spirv_bin" --version > /dev/null || fail "Profiling run failed"
  debug "✅ Profiling binary found at: $spirv_bin"
}

function install_final_build() {
  log "🧹 Removing existing install directory: $PREFIX"
  sudo rm -rf "$PREFIX"
  sudo cmake --install "$BUILD_DIR_USE"
}

function validate_install() {
  local spirv_bin="$PREFIX/bin/llvm-spirv"
  [[ -f "$spirv_bin" ]] || fail "llvm-spirv not found after install!"
  debug "✅ llvm-spirv installed to: $spirv_bin"
}

# === MAIN BUILD SEQUENCE ===

function build_spirv_llvm_translator() {
  log "📦 Building SPIRV-LLVM-Translator with PGO and aggressive optimization..."
  rm -rf "$ROOT"
  mkdir -p "$ROOT"
  cd "$ROOT"

  log "📥 Cloning fresh SPIRV-LLVM-Translator repository..."
  git clone --depth=1 --branch llvm_release_180 https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git spirv-llvm-translator || fail "Clone failed"
  [[ -d "spirv-llvm-translator" ]] || fail "spirv-llvm-translator directory missing after clone"

  # First Pass: Generate profiling data
  log "🔁 First pass: -fprofile-generate"
  build_with_flags "$BUILD_DIR_GEN" "-fprofile-generate=$PROFILE_DIR" "Generate"
  run_profiling_workload

  # Second Pass: Use profiling data
  log "🎯 Second pass: -fprofile-use"
  build_with_flags "$BUILD_DIR_USE" "-fprofile-use=$PROFILE_DIR -fprofile-correction -Wno-missing-profile" "Use"
  install_final_build
  validate_install
}

# === MAIN EXECUTION ===
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  build_spirv_llvm_translator
fi
