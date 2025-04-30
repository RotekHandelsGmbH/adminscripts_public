#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
PREFIX="/opt/mesa"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/libclc-build"
LLVM_VERSION="18"
LLVM_CONFIG="llvm-config-${LLVM_VERSION}"
LLVM_PROJECT_DIR="$ROOT/llvm-project"
PROFILE_DIR="$ROOT/profile-data"
BUILD_GEN="$ROOT/build-gen"
BUILD_USE="$ROOT/build-use"

mkdir -p "$ROOT"

# === Color Log Functions ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; RESET='\033[0m'
log()    { echo -e "\n${CYAN}ℹ️  [INFO]${RESET} $1\n"; }
debug()  { echo -e "${BLUE}🐞 [DEBUG]${RESET} $1"; }
warn()   { echo -e "${YELLOW}⚠️ [WARN]${RESET} $1"; }
success(){ echo -e "${GREEN}✅ [SUCCESS]${RESET} $1"; }
error()  { echo -e "${RED}❌ [ERROR]${RESET} $1" >&2; }
fail()   { error "$1"; exit 1; }

# === Compiler Setup ===
log "🛠️ Using GCC as the compiler"
export CC=gcc
export CXX=g++

# === Clone Repo if Needed ===
fetch_repo() {
  if [ ! -d "$LLVM_PROJECT_DIR" ]; then
    git clone --depth=1 --branch llvmorg-${LLVM_VERSION}.1.0 https://github.com/llvm/llvm-project.git "$LLVM_PROJECT_DIR" || fail "llvm-project clone failed"
  else
    log "Using existing llvm-project at $LLVM_PROJECT_DIR"
  fi
}

# === Apply Patch to CMakeLists.txt if Required ===
patch_cmake_if_needed() {
  cd "$LLVM_PROJECT_DIR/libclc"
  if ! grep -q "find_package(SPIRV-Tools" CMakeLists.txt; then
    log "Patching CMakeLists.txt for SPIRV-Tools..."
    sed -i '2i\
find_package(SPIRV-Tools REQUIRED CONFIG)\nset(SPIRV-Tools_INCLUDE_DIR "'"$PREFIX"'/include")\nset(SPIRV-Tools_LIBRARY "'"$PREFIX"'/lib/libSPIRV-Tools.a")\n' CMakeLists.txt
  fi
}

# === Build Function ===
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

  cmake -S "$LLVM_PROJECT_DIR/libclc" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_CONFIG="$LLVM_CONFIG" \
    -DENABLE_SPIRV=ON \
    -DCMAKE_PREFIX_PATH="$PREFIX;$PREFIX/lib;$PREFIX/lib/cmake" \
    -DCMAKE_MODULE_PATH="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DSPIRV_TOOLS_INCLUDE_DIR="$PREFIX/include" \
    -DSPIRV_TOOLS_LIBRARY="$PREFIX/lib/libSPIRV-Tools.a" \
    -DSPIRV-Tools_DIR="$PREFIX/lib/cmake/SPIRV-Tools" \
    -DLLVM_SPIRV="$PREFIX/bin/llvm-spirv"

  cmake --build "$BUILD_DIR" -- -j"$(nproc)"
}

# === Run Profiling Workload (Dummy) ===
run_profiling_workload() {
  log "⚡ Running profiling workload..."
  # Replace this with actual usage (e.g. compiling kernels)
  find "$BUILD_GEN" -type f -executable -exec {} \; || true
}

# === Install Final Build ===
install_final_build() {
  sudo cmake --install "$BUILD_USE"
  success "libclc installed to $PREFIX"
}

# === MAIN BUILD FLOW ===
log "🚀 Starting 2-pass PGO build for libclc..."

fetch_repo
patch_cmake_if_needed

log "🔁 First pass: -fprofile-generate"
build_with_flags "$BUILD_GEN" "-fprofile-generate=$PROFILE_DIR" "Generate"
run_profiling_workload

log "🎯 Second pass: -fprofile-use"
build_with_flags "$BUILD_USE" "-fprofile-use=$PROFILE_DIR -fprofile-correction -Wno-missing-profile" "Use"
install_final_build
